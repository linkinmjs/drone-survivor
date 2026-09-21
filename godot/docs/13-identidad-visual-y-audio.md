# 13 — Identidad visual y audio

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-24, WP-25, WP-26, WP-27, WP-28 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/04-especificacion-configuracion-y-menus.md`, `docs/10-ciudad-destructible.md`, `docs/12-interfaz-y-hud.md`

## 1. Objetivo y alcance

> **Nota del checkpoint 4 (2026-09-21, legibilidad)**: el usuario reportó que los disparos y las luces de fondo dificultaban la visión. Medido con `tools/legibility_shots.tscn` (batalla congelada, cada encuadre con y sin fogonazo, `--flash`, `--tweak`, `--emission`) y Movie Maker (461 fotogramas): el fogonazo lavaba el centro (+20 % de luminancia en la caja del jefe, −90 % de sus píxeles cian a 40–80 m) y el glow envolvía la ciudad en un velo (14 % del cuadro a 30 m de las ventanas, 18 % en vuelo bajo). Causa del fogonazo: las **ocho chispas** (ver `docs/08`), no la luz ni el quad. Glow (`build_environment.gd`, regenerado con `take_over_path()` y uid conservado): `glow_intensity` 0,85 → **0,60**, `glow_hdr_threshold` 1,4 → **1,70**, niveles 5/6 0,6/0,2 → **0,30/0,05** (mipmaps anchas = ancho del halo); `glow_bloom` y niveles 2–4 iguales; exposición, tonemap, viñeta y haces sin tocar (el haz de asedio quemaba 0,10 % del cuadro). Fachadas: `emission_energy_multiplier` de las cuatro familias a **0,65** (fachada a 8 m de 0,28 % a 0,00 % de píxeles > 0,90; el racionado de ventanas se conserva). Después: manchón central 5,1 → 2,0 % de media, fotogramas con manchón 97 → 29 de 270, caja del jefe +1,6 %, cian borrado −5 % a 60 m, velo 14 → 7 % y 18 → 8 %, halo por ventana 3,2/10,3/14 → 2,3/8,7/12 px (media/p90/máx; el p90 lo dominan racimos de ventanas contiguas, no una ventana suelta); `environment_shots` con altos que dejan de reventar (`high_a_aces_intro` p99 0,987 → 0,922) y el reparto frío/cálido igual (73/16 %). §3.1 y §9 (glow) quedan corregidos por esta nota. Palancas medidas y no aplicadas: variante dura de glow (0,55 · umbral 2,0: halos de 0,3 px, contradice la identidad), energía de la luz del fogonazo 1,5 → 2,5 si se lee flojo.

> **Nota del cierre de la revisión de la tanda 4 (2026-09-20)**: revisión de código de solo lectura (`godot-code-reviewer`) con 1 hallazgo bloqueante, 6 importantes y 12 menores, todos corregidos por los agentes dueños. **VFX**: la retención larga la declara el catálogo (`SPECS` con `hold: true` en `laser_beam`, `siege_beam` y `damaged_sparks`) y la red de `MAX_HOLD_SECONDS` (120 s) ya no las reclama (avisa una vez); antes apagaba el haz a los dos minutos de pelea, lo sacaba del conteo de emisores y, si el jefe moría con el haz encendido, quedaba emitiendo. `release()` sobre una ranura ya reclamada apaga igual el efecto; `acquire()` comprueba el presupuesto con el coste neto **antes** de reciclar (un pedido denegado ya no apaga el efecto más viejo); el pool se desconecta del bus en `_exit_tree()` y apaga su `_process` sin ranuras activas; `Telegraph` devuelve su efecto en `NOTIFICATION_EXIT_TREE` (un decal rojo de 18 m ya no queda parpadeando en la calle si el enemigo muere en pleno aviso); `Building` distingue plazas reservadas en el pool (`_pool_reserved`) y resetea sus estáticos al salir del nivel; `impact_fx.tscn` cumple el contrato de §4 (`fixed_fps 30`, `interpolate`, `VIEW_DEPTH`). **Cupo aceptado**: un efecto `hold` cuesta 0 apagado y se cobra al encenderse, así que con el presupuesto justo lleno puede haber **13 emisores en vez de 12** mientras dura un haz (+1 como mucho: los dos haces son excluyentes por enemigo); cobrarlo al pedir impediría que `hide_beam()` devuelva presupuesto entre ventanas, que es lo que deja alternar haz e impactos. **Audio**: `ImpactFXPool` cacheado, reintento del bucle del haz cada 500 ms, `set_physics_process` solo en transiciones, y **la intensidad musical de §5.3 cableada**: `cercanía = clamp((160 − d)/(160 − 30), 0, 1)`, `calor = clamp(daño reciente/60 hp, 0, 1)` con decaimiento lineal en 5 s, `v = 0,5·cercanía + 0,5·calor` solo en BATTLE (fuera, `v = 0,5`), desvío `(2v − 1)·6 dB` por rampa a 24 dB/s (0,48 dB por 20 ms); distancia muestreada a 4 Hz entre el grupo `enemies` y el grupo `fpv_camera`, `null` seguro; `@export auto_intensity`. **Cámara/HUD/overlay**: `CameraRig` conecta y desconecta `camera_trauma` y `QuadSettings.settings_updated` en `_enter_tree`/`_exit_tree` y apaga su `_process` sin sacudida (`auto_tick` para los checks); `HUDSignalIndicator` procesa solo bajo `CRITICAL_QUALITY`; `FPVOverlay._time` se repliega cada 600 s (mínimo común múltiplo de sus cuatro periodos, sin salto de fase); `fpv_overlay_full()` con `CUSTOM` sigue a `shadows` (documentado). El doble trauma del aterrizaje de `pounce` (0,5 + 0,9 → 1,0) queda como está, a propósito.

> **Nota de WP-29 (2026-09-20)**: medido con la máquina tranquila: el ojo de pez FAST_WIDE es el **96,7 % del GPU** de `boss_and_city` en HIGH (frontal 5,6 ms, laterales 1,1 y 1,0, raíz 0,26; total 7,7–8,1 ms) y es la única palanca de fps en HIGH (120 fps de reloj, p1 76–81: cumple con margen); el overlay FPV cuesta **0,10 ms** y 1 draw call (ablación; §7 pedía ≤ 0,25); los VFX en reposo, 4 draw calls y ≈ 0 GPU; la sacudida, nada medible. `render_check` da 873 draw calls máximos con todo el contenido de la tanda 4 (tope 900). La fila «Ojo de pez» de §3.4 queda corregida abajo (HIGH y ULTRA son FAST_WIDE 1080p desde WP-24c; FULL sigue en el menú). `drone/weapons/impact_fx.tscn` era el único `GPUParticles3D` sin `fixed_fps = 30` (§4): se corrige en el cierre de la revisión.

> **Nota de WP-28 parte B (2026-09-20, sacudida real)**: `CameraRig` implementa §6 con estas precisiones: ruido simplex en tres carriles por canal (`TRANSLATION_LANES` 0/37/74 y `ROTATION_LANES` 111/148/185: con los mismos seis números girar y trasladar quedaban en fase y la cámara se movía como pieza rígida sobre un riel), vector acotado con `limit_length(1.0)` para que **0,08 m y 2,5° sean máximos de módulo** (medido con trauma 1,0: pico 0,051 m y 1,43°, ~60 % del tope; si se quiere sentir al tope, la palanca es subir los máximos), base capturada del nodo al empezar la sacudida y recompuesta con `set_tilt_degrees`, sin escritura de la transformada cuando no hay sacudida, listener conectado en `_ready`; API extra `is_shaking()`, `clear_trauma()`, `tick()`, `translation_offset()`, `rotation_offset()`, `base_position()`, `base_rotation()`, `noise_seed()`/`set_noise_seed()`. Trauma 1,0 se extingue en 0,7167 s medidos. Emisores nuevos: `WeaponMount.SHOT_TRAUMA` 0,03 en `fire()`, `Hull.IMPACT_TRAUMA` 0,25 en `apply_damage()`, `EnergySystem.EMP_TRAUMA` 0,60 en `apply_emp()`, `ObjectiveSequencer.SUCCESS_TRAUMA` 0,08 con `Vector3.INF` (sin atenuación) al pasar a `SUCCESS`. **La fila «Derrumbe» de la tabla de §6 queda corregida abajo**: manda `docs/10` (0,65 en DAMAGED y 0,85 en RUBBLE, dos eventos; `low_block` 0,45/0,65); `docs/10` §5 hablaba de un radio de 120 m sin piso y queda alineado con los 80 m y el piso 0,15 de este doc. El aterrizaje de `pounce` emite dos traumas en el mismo cuadro (0,5 del rig + 0,9 de la acción, recortados a 1,0): intencional por ahora. La señal se publica desde `DroneRig._feed_hud()` (`FlightHUD.set_signal_quality(overlay.signal_quality())`), `HUDSignalIndicator.CRITICAL_QUALITY` 0,34 → 0,25 (parpadea solo con una barra), y **`"signal"` entra en el preset de HUD `standard`** (decisión del cierre: sin eso el jugador no veía la degradación). `shake_check` 10 filas (§10.4 corregido abajo). `hud_projection_check` esconde el `Rect` del overlay al medir: la columna FULL/25°/12°/0,94·w volvió a 2,1 px en tres corridas; el peor error ahora es FAST_WIDE/15°/0°/0,94·w con 7,48 px (tolerancia 8) y depende de si `coverage()` la declara medible: es el candidato si esa fila vuelve a ponerse roja. `LevelBase.warm_up_view()` escribe `FPVCamera.rotation.y` durante el calentamiento (restaura antes del juego): excepción conocida a «la FPVCamera cuelga con identidad». `flight_bench` idéntico en todas sus métricas de física.

> **Nota del cierre de WP-27 (2026-09-20)**: los efectos de WP-26 que no tenían hecho de bus suenan por bucles del **`AudioPool`** (no del `AudioRig`: en el rig un haz sumaba una novena voz al presupuesto propio del jefe y `arachnodroid_check` habría cambiado; en el pool cuentan en el tope de 6 de `enemies` junto con lo que declara el rig): `play_loop(event, position, anchor)`, `move_loop()`, `stop_loop()` idempotente, `set_anchored_loop(event, anchor, active)` (uno por ancla), `loop_count()`, `active_loops()`, estáticas `resolve()`, `emit_event()`, `toggle_loop()`. Una voz de bucle queda retenida (el reciclaje por lejanía no la toca) y su ancla marca hasta cuándo vive: si el nodo se libera, el pool corta la voz en el mismo tick (`is_instance_valid()`, no `!= null`: un objeto liberado compara igual a `null` y el zumbido sobrevivía al enemigo). Ganchos: `SweepAction.update_beam()`/`hide_beam()` (los dos haces; `&"SiegeBeam"` → `siege_loop`, si no `laser_loop`; pool cacheado por acción para `NOTIFICATION_EXIT_TREE`), `ActionEmpPulse` tras `flash_ring()` → `emp_ring` (junto al `emp_burst` del rig), `EnemyPart` bajo el 35 % (`AudioPool.SPARKS_RATIO`, espejo de `VFXPool.DAMAGED_RATIO`) → `sparks_loop` con tope de 2. Sonidos nuevos en `assets/audio/combat/` (44,1 kHz, pico −6 dBFS, costura del bucle medida contra el máximo interior): `laser_loop` 2,0 s (dos portadoras a ~2 kHz con batido, pasa-altos 900 Hz; −6 dB, `unit_size` 24), `siege_loop` 2,5 s (sub-graves 44/67/91 Hz + crepitar granular; −3 dB, 24), `sparks_loop` 1,6 s (descargas de ruido agudo; −10 dB, 16), `emp_ring` 1,2 s (silbido que se cierra de 6 kHz a 300 Hz mientras el tono cae: «se aleja»; −2 dB, 48). Pisadas: `AudioRig.play_footstep()` ya escala con `impact_speed` (0–14 m/s → −14…0 dB); pila sin zumbido de reposo (cinco activas se llevarían 5 de las 6 voces de `city`).

> **Nota de WP-28 parte A (2026-09-20, overlay FPV)**: `drone/fpv_camera/fpv_overlay.gd` (`FPVOverlay extends CanvasLayer`, capa −1, `Rect` full-rect creado en código) es el nodo `Overlay` de `drone_rig.tscn` (después del `Drone`, porque seis escenas lo sobrescriben por `index="0"`); `DroneRig.get_overlay()`. API: `set_damage/damage`, `set_emp/emp` (fija y congela), `trigger_emp(glitch_seconds)`/`emp_remaining()`, `set_full_quality/is_full_quality`, `signal_quality()` = `clampf(1 − 0,75·damage, 0, 1) · (1 − 0,7·emp)` (`static quality_for`, `DAMAGE_WEIGHT`, `EMP_WEIGHT`), `material()`, `rect()`, `tick(delta)`/`clock()`. Se alimenta solo: `hull_changed` → `damage = 1 − ratio`; `drone_respawned` → relee el `Hull` real (que siempre vuelve a 100 %: el 60/20 % de `docs/09` es de la batería) y `emp = 0`; `EnergySystem.emp_hit` local, reenganchada en cada respawn; el `Rect` se esconde cuando la `FPVCamera` no es `current`. **Correcciones a §7**: (1) `screen_tex` con `filter_linear`, **no** `filter_linear_mipmap`: pedir mips obliga a generar la cadena de la copia del backbuffer cada cuadro (base +0,242 → +0,078 ms; con mips el estado de EMP se pasaba de 0,25 ms) y la imagen es idéntica; (2) el grano es **multiplicativo y pesado a los medios tonos** (`col *= 1 + ruido·4·L·(1−L)`), no aditivo: un `+= 0,035` recortado en 0 llenaba de nieve la viñeta honesta de FAST, rompía la fila [11] de `hud_projection_check` (0,040 de contraste en su escena) y la comparación A/B de la [14]; (3) **dos shaders**: `fpv_overlay_low.gdshader` (solo viñeta, sin `hint_screen_texture`, que fuerza la copia aunque no se lea) para LOW vía `Graphics.fpv_overlay_full()`, con el latido de 1,5 Hz conservado; (4) uniforms extra `time` (reloj por script, nada de `TIME`), `danger_color` (= `UIPalette.DANGER`, aseverado) y `emp_seed` (rota por pulso); (5) el tinte de daño vive en la corona (`smoothstep(0,60, 1,35, radio)`, 55 % máximo, contra la luminancia): a daño 1,0 el centro no cambia ni 1 % de croma («señal enferma, no filtro rojo»); (6) «desatura hasta 0,2» = queda 0,2 de saturación (`EMP_SATURATION`). Constantes: bloques EMP de 24 filas a 18 Hz con corrimiento ≤ 0,055 UV, barra blanca-ámbar de 0,6 s, grano a 24 Hz en celdas de 3 px, viñeta `smoothstep(0,55, 1,45, radio)`. **Coste medido** (1080p, RTX 3060, viewport raíz con ojo de pez): apagado 0,171 ms; base +0,064; daño 1,0 +0,072; EMP 1,0 +0,093; LOW 0,145; +1 draw call (`render_check` 870 < 900; 120,7 fps HIGH informativos con otro agente trabajando). Capturas leídas: la base no se nota (centro −3 %, esquina 0,36 por la viñeta de 0,35: es el número a bajar si molesta), daño 1,0 con centro intacto y rojo solo en la corona, EMP con desgarro por bloques y HUD nítido y con todo su color encima. `overlay_check` 7 filas + negativa (`docs/15` §1). Riesgo que hereda la parte B: la columna FULL/25°/12°/0,94·w de `hud_projection_check` [11] quedó inestable con el overlay (5,8 / 6,0 / 253 px): se esconde el `Rect` durante la medición.

> **Nota del cierre de WP-26 (2026-09-20)**: hecho lo anunciado en la nota anterior: `hit_confirmed` con `surface` (§8 queda corregido: `impact_armor` / `impact_weak` / `impact_city` salen de `surface`; `world` no dibuja), `impact_armor` sin `Decal` (mismo coste: 1 emisor, pool 12; los nodos de `vfx_check` bajan de 205 a 193), `ActionHeadLaser.BEAM_RADIUS` 0,6 m, luz de carga del `Telegraph` 90 000 → **30 000 lm** y 60 → **40 m** para todos los avisos (`TelegraphProfile` no tiene brillo absoluto por ataque: `light_energy_to` es la forma de la rampa; si hiciera falta por ataque, el campo nuevo sería `light_lumens`). Rojo medido en el mismo pisotón y la misma semilla (píxeles con R dominante y G≈B, a cuarto de resolución): batalla con el bot a 33 m, fotograma 590, **20,3 % → 5,1 %**; showcase aéreo, fotograma 199, 21,1 % → 4,5 %. Dos bugs encontrados al confirmar el cráter: (A) `VFXDecalZone` y `VFXRing` (`life_seconds = 0`) nunca terminaban al entregarse con `release_when_done()` y retenían la ranura hasta la red de 120 s: con `_struck`/`_flashed` la tasa de denegación de la tanda de 200 pedidos cae de 27,5 % a **11,0 %**; (B) la caja del `Decal` del pisotón está centrada en su origen y con `PROJECTOR_HEIGHT` 3 m la calle caía en el borde inferior donde `lower_fade` la desvanece: ahora 0 m, `normal_fade` es lo que evita pintar torres y patas. El aviso pasa a ser emisivo (`vfx_emissive`, `emission_energy 4,0`; cráter con rescoldo 0,6 y polvo claro) porque el pie cae casi siempre en la sombra del propio coloso. Cráter confirmado (disco de polvo claro con once grietas radiales, 0,9 s tras el golpe). `vfx_check` 13 filas (12 «zona del pisotón: sigue → congela → golpea → cráter de 4 s», 13 «anillo del EMP: crece → destella 0,3 s → vuelve al pool»); `enemy_showcase` gana `--drone=x,y,z`.

> **Nota de WP-26 (2026-09-20, VFX)**: entregado según §4 con estas precisiones. `vfx/vfx_pool.gd` (`VFXPool`, nodo `Pools/VFXPool`, grupo `vfx_pool`, `VFXPool.resolve(node)`): **56 instancias preasignadas** en `_ready()` para 18 ids (no crea ni libera nodos después), LRU por id antes que el presupuesto, `budget()` = `Graphics.max_emitters()` (6/8/12), `active_emitters()` cuenta las ranuras cuyo efecto sigue sonando (conservador: un `one_shot` apaga `emitting` antes de que mueran sus partículas; en la tanda del check el pico contado fue 12 y el medido 6); extensiones `acquire(id, xform, parent, scale)`, `reserve_emitters()`/`release_emitters()` (las usa `Building`), `release_when_done()`, `follow()`, `measured_emitters()`. `request(…, parent)` **no reparenta**: `parent` es el nodo al que seguir (reparentar rompía el reciclado y el conteo estable de hijos de §10.2). Catálogo (id → emisores / pool): `impact_armor` 1/12, `impact_weak` 1/8, `impact_city` 1/8, `foot_dust` 1/4, `collapse` 2/2, `part_detach` 2/4, `laser_beam` 1/1, `siege_beam` 1/1, `siege_column` 0/1, `emp_ring` 0/1, `stomp_decal` 0/2, `guide_line` 0/1, `parabola` 0/1, `damaged_sparks` 1/4 (único continuo: tope propio de ¼ del presupuesto), `drone_sparks` 1/2, `drone_burst` 2/1, `pickup_flash` 1/2 (fila nueva, por `battery_collected` de §8), `muzzle_flash` 0 (fijo en `WeaponMount`, mejorado en su sitio: luz de 3 m, energía 4→0 en 0,06 s, 8 chispas, quad emisivo; cierra la discrepancia de WP-14 con `docs/08` §2.10). Decisiones: los 32 decals de bala de `ImpactFXPool` se conservan como capa por bala (son el tope de 32 de §9); el `DustBurst` por edificio pide plaza al pool y la columna `Smoke` la reemplaza `collapse` con su `FogVolume` (dos contadores de 12 daban 24 emisores); el halo de la pila es un `MultiMesh` de 6 motas (0 emisores) y el prop `vfx/battery_cell.tscn` es procedural en 3 draw calls (una versión de 11 `MeshInstance3D` subió `render_check` de 828 a 905 draw calls y **falló** el tope de 900; con `MultiMesh` da 869); `ImpactFX` variante `WEAK` pasa de ámbar a **cian**; los haces los retiene el pool y `hide_beam()` solo apaga (`beam_node()` estable para `arachnodroid_check` 15). `beam.gdshader`: núcleo con exponente 6 (con 2 se comía el matiz de un haz fino), `laser_beam` cian con `intensity` 4,2, `siege_beam` ámbar-naranja (la excepción cálida). Correcciones que salieron de mirar 13 fotogramas: caja del decal del pisotón 9/14 → 3/6 m con `normal_fade 0,75` (pintaba la torre y las patas), `FogVolume` del polvo 0,32 → 0,045 con `edge_fade` 0,75 (se veía como una losa gris) y `collapse` 0,24 → 0,05, relleno del anillo de zona 26 → 10 %, cráter claro sobre asfalto oscuro, `VFXGuide` sin `surface_end()` vacío. `vfx_check` 11 filas (200 pedidos en 20 s: 145 servidos y 55 denegados; hijos 56/56, nodos 205/205, huérfanos 0; prueba negativa que retiene un `emp_ring` fuera de la tanda). `perf_report --suffix=-wp26` (`docs/perf/2026-09-20-wp26.json`, máquina compartida): draw calls 543 media / 553 máx, 183,9 fps de reloj, GPU 4,87 ms. Cierre corto en curso: `hit_confirmed` gana `surface` (se retira la heurística «≤ 30 m del jefe = blindaje»), sin decal en `impact_armor`, haz del láser a 0,6 m, luz de carga del pisotón atenuada.

> **Nota de WP-27 (2026-09-20, audio)**: entregado según §5 con estas precisiones. **Buses** generados por `tools/build_bus_layout.gd`: `Master` 0 dB con compresor (−12 dB, 4:1, 20/180 ms) + limitador (−0,5 dB); `Motors` −4, `Weapons` −3, `Enemies` −2, `City` −5 con reverb (0,6/0,4/0,12), `UI` −6, `Music` −8 con pasa-bajos de 600 Hz **deshabilitado** que `PauseMenu` enciende al pausar; los deslizadores del jugador se **suman** en dB sobre esa base (`Audio.BASE_VOLUMES_DB`; `docs/04` §3.3 queda corregido). **`AudioPool`** (`audio/audio_pool.gd`, nodo `Pools/AudioPool`, grupo `audio_pool`): 24 voces creadas en `_ready()`, topes 4/6/6/6/2, desalojo de la voz más lejana al oyente (empate: la más vieja) y descarte del pedido (`null`) si entra más lejos que la peor; `play_event(id, position)` sobre un banco propio (`assets/audio/combat/`, `assets/audio/city/`, sintetizado por `generate_pool_sounds.gd` y `generate_city_sounds.gd`); `register_source()` para fuentes externas (`MotorAudio` en el grupo `audio_motors`, `AudioRig` en `audio_enemies` con `can_claim()`); doppler `PHYSICS_STEP` en armas y enemigos con reinicio del rastreador al reciclar. El pool **no** toca `shot_fired` (ya lo hace `FireSound` del arma) y en `hit_confirmed` agrega siempre el timbre del punto débil y el de blindaje solo si `ImpactFXPool` no trae sonido (`armor_policy`). Buses decididos para los eventos sin bus en §8: `hull_hit` en `Weapons`; `signal_cut` y `power_up` (muerte y arranque del dron) en `Motors`. `damage_crack` se engancha a `Building.stage_changed` recorriendo el grupo `buildings` en cada cambio de estado de ronda. **Música**: `AudioStreamSynchronized` con volúmenes por `set_sync_stream_volume()` (el `AudioStreamPlaybackSynchronized` no expone métodos en 4.7); stems **WAV PCM 16 bits mono a 32 kHz** (Godot no codifica OGG desde GDScript; 4 MiB cada uno), 64,000000 s exactos, Am·F·Dm·E5 a 120 BPM con osciladores por tabla de onda y eventos plegados sobre el principio para que el bucle empalme; RMS/pico: `ambient` −24,0/−12,3, `tension` −21,0/−7,9, `combat` −19,5/−1,0 dBFS; stings de 2,6 y 3,2 s; cruces medidos a 0,18 y 0,87 dB por 20 ms, sin sobrepasos. El criterio de §10.3 fila 5 (posición ±5 ms) no es medible: lo reemplaza la garantía estructural (mismo recurso, mismas muestras comparadas al sample, prueba negativa) más una deriva del reloj de mezcla < 25 % (con el controlador Dummy varía entre 0,2 y 2,5 % entre corridas). Ambiente nocturno (`ambience_night`, bucle de 20 s: viento, ciudad dormida y una radio lejana con voz filtrada sin palabras) a −18 dB en `City` durante `BATTLE`. `tools/audio_showcase.tscn` imprime los picos por bus de 20 s de mezcla (no forma parte de la suite). Sin fuentes de terceros: nada que anotar en `CREDITS.md`.

> **Nota de WP-25 (2026-09-20, identidad «Última luz»)**: `UIPalette` es ahora la tabla oscura de §2.2 con estos ajustes: `HUD_TEXT` **ámbar `#FFD08A`** (no `#E8F4F8`: el HUD de vuelo va en ámbar sobre la señal y nada propio es cian), `HUD_BOX` relleno oscuro translúcido (`#050D12` @ 42 %, no cian), `HUD_SHADOW` negro @ 70 % con contorno de **3 px** (no 4: con trazo de 1,6 px engorda la letra), `HUD_REC = DANGER` (un solo rojo de alarma), `GRAPH_AXIS #6E808D` (el `#5A6B78` daba 3,44:1 y abortaba la verificación), `HUD_TRACK`/`HUD_DIM`/`HUD_STROKE 1,6`/`HUD_OUTLINE 3`, `SURFACE_DISABLED`, `ACCENT_HOVER/SOFT`, `DANGER_SOFT/HOVER/BORDER`, `TEXT_ON_ACCENT`; alias históricos conservados; `CombatHUDPalette` es alias puro. `GRAPH_ROLL` dejó el cian por `#7FA4C0` (cian solo diegético; aplicado por WP-25b pantalla, temas regenerados). La fila `HUD_REC` de §2.2 ya no corresponde a un componente («punto REC» no existe): es el rojo de alarma de `HUDDraw.ALERT`. Tipografías OFL en `gui/theme/fonts/<familia>/` con `LICENSE.txt`: Chakra Petch SemiBold/Regular, Barlow Semi Condensed Regular/Medium, **JetBrains Mono variable** (`static/` no existe en Google Fonts; `FontVariation` a `wght 500`); cuerpos reales 60/44/32/20 (display/título/encabezado/sección), Barlow 20/18/16, mono 24/18. `ThemeBuilder`: radio **2**, `corner_detail 2`, bordes de 1 px, foco ámbar de 2 px, sin sombras difusas (`with_shadow` eliminada), íconos procedurales rectangulares, variaciones nuevas (`MonoLabel`, `MonoSmallLabel`, `CodeLabel` cian = voz enemiga, `LoadingLabel`, `LoadingTipLabel`, `CardPanel`, `HudPreviewPanel`, `OverlayScrim`), **`build_hud()`** genera `hud/hud_theme.tres`, y `verify_contrast()` aborta si algún par baja de 4,5:1. Imperfección propia: `MarkerUnderlineStyle` (subraya de rotulador con temblor sembrado, extremos que adelgazan y un salto) solo en `HeadingLabel`/`SectionLabel`. Pantalla de carga «del taller» (`Scanlines`, `LoadingSpinner` de 7 puntos ámbar, «Cargando el barrio…»). Sonidos UI regenerados con timbre de hojalata (armónicos impares, tercer parcial desafinado 1,2 %) sin cambiar niveles. Dron de pieza suelta (paleta de 17 índices, brazo rojo y brazo negro, cinta en el motor 2, batería con parche, LED ámbar, 11 vóxeles de detalle; 16 partes, pivotes, colisiones y masa idénticos). `menu_shots_check` (§10.5) captura **10** pantallas (las 8 + pausa + tarjeta) y falla ante claves crudas; registrado con ventana en los runners. El backdrop 3D del menú (§2.5) sigue sin hacerse. Licencias de las fuentes: pendientes de `CREDITS.md`/`docs/16` por política.

> **Nota de WP-24e (2026-09-20)**: `rendering/occlusion_culling/use_occlusion_culling = false` y ninguna `SubViewport` del ojo de pez la pide en ningún preset (`settings_check` lo asevera sobre una `FPVCamera` real): la oclusión no ahorraba nada medible (−0,011 ms) y producía los parpadeos por los oclusores de la ciudad. El umbral de LOD de las caras laterales de FAST_WIDE pasa a ser el del preset (se retira el suelo de 4 px) para que ningún prop cambie de LOD al cruzar la costura. `render_check` HIGH 131 fps / p1 88; LOW 625.

> **Decisión de identidad (checkpoint 3b, 2026-09-20)**: el usuario juzgó que «toda la estética se ve igual al drone simulator» (paleta clara, Recursive, radios de 10 px, HUD blanco copiado tal cual) y eligió, sobre su propio `docs/narrativa/identidad-visual-opciones.md`, la dirección **A · Última luz** con los dos préstamos de B (la señal se degrada con el daño y hay estática al reconstruir; ventanas racionadas por bloque) y las tres reglas de coherencia (nada enemigo es cálido y nada propio es cian; lo propio tiene imperfección; la ciudad se muestra antes que el puntaje). Concreciones acordadas para WP-25: paleta oscura de §2.2 aplicada de verdad a `UIPalette` (con `CombatHUDPalette` como alias), fuentes OFL de §2.3 con roles por voz (Chakra Petch = títulos y códigos enemigos; Barlow Semi Condensed = voz propia; JetBrains Mono = readouts), `ThemeBuilder` con radio 2 px y líneas de 1 px regenerando también `hud_theme.tres`, encabezados con una subraya «de rotulador» procedural como única imperfección de menú, pantalla de carga «del taller» (ámbar sobre negro), **HUD de vuelo con el mismo instrumental pero otro estilo** (ámbar sobre la señal, trazo fino con contorno oscuro, JetBrains Mono, y el indicador «REC» reemplazado por uno de **SEÑAL**), dron de «pieza suelta», estática al morir y al volver (`GlitchLayer.trigger_static`, reutilizando el `StaticBurst` de la alerta), contador de drones del taller en la reconstrucción, ventanas racionadas (30 % de las **manzanas**, de tamaño fijo, con semilla; todos los edificios de la manzana sorteada), y `menu_shots_check`. El backdrop 3D del menú (§2.5) queda como opcional al final de P2. La narrativa (`docs/narrativa/narrativa.md` §5 y §8) suma la **alerta del monitor del taller** antes de cada nivel y el **edificio protegido con nombre** (diseño en `docs/11` §1).

> **Nota de WP-24 (2026-09-20, entorno y luz)**: la ciudad «plana, gris y de mediodía» tenía dos bugs medibles: (a) los cuatro materiales de ciudad tenían `emission = blanco` con `emission_operator` **ADD** (`EMISSION = (emission + textura) · energía`), o sea 1 000 nits uniformes sobre cada píxel de cada fachada y el bake de ventanas (1,9 % de téxeles) no pintaba nada → `emission_operator = MULTIPLY` en `buildings_001/002`, `props`, `roads` (fachada 2,12 HDR → 0,00–0,03; ventana 2,21); (b) la escena estaba calibrada para mediodía: sol 100 000 lux × 1,45, `background_intensity` 30 000 nits de fábrica y cámara f/16 · 1/100 s · ISO 100, con lo que los emisivos de 1 000 nits salían a 0,033 (30× bajo el umbral de glow). Ahora: `world/environment_battle.tres` lo escribe **`tools/build_environment.gd`** (headless; también `sun_dusk.tres`, `camera_attributes_dusk.tres`, `environment_menu.tres`), con la tabla de §3.1 salvo: `sky.process_mode QUALITY` (`HIGH_QUALITY` no existe en 4.7), **`background_intensity` 1 100 nits** (falta en §3.1 y es la mitad del problema), `reflected_light_source SKY` (propiedad nueva de 4.7), niebla de profundidad `density 0,0006` / `light_energy 0,22` / `aerial_perspective 0,25` (a 0,0016 levantaba todos los negros a 200 m), niebla volumétrica `density 0,0008` / `ambient_inject 0,15` (0,012 sobre 96 m era 68 % de niebla), glow `hdr_threshold 1,4` / `bloom 0,03` (con 0,95 el cielo entero entraba al glow), **`tonemap_agx_contrast 1,35`** (`tonemap_contrast` no existe; `tonemap_white` solo lo lee ACES; AgX usa `tonemap_agx_white` 16,29), ajustes 1,0 / 1,04 / 1,06 y **sin LUT** (el reparto frío/cálido 73 %/15 % ya sale por física; `build_environment.gd` la enchufa si el archivo existe). **Exposición** en `world/camera_attributes_dusk.tres` compartido: **f/2,8 · 1/100 s · ISO 400** (+7,03 pasos; el sol baja 5,92 → superficies ×2,16 y emisivos ×131, a ~4,3 HDR) y no en `tonemap_exposure`, porque el glow se extrae antes del tonemap. **`SunProfile`** (`world/sun_profile.gd`, `sun_dusk.tres`) + `SunLight extends DirectionalLight3D @tool` (`world/sun_light.gd`): 2 400 lux, 3 200 K → `light_color #FFB87B` derivado (con `light_temperature` en 6 500 para no calentar dos veces), (−6°, −118°), `angular_distance 0,6`, `volumetric_fog_energy 1,6`; las sombras las pone `Graphics.apply_sun_quality()` por preset, y `Graphics.register_sun()` vuelca el perfil a cualquier sol que no sea `SunLight`. **`ReflectionProbeRig`** (`world/reflection_probe_rig.gd`) crea en runtime 0/2/4/6 probes `UPDATE_ONCE` por preset en el cruce de avenidas, avenidas, azoteas de hitos y calle lateral (posiciones de la API de `CityGrid`); nada horneado en `district_a`. `city_check._check_gi_modes()`: 89 mallas STATIC / 180 DISABLED por rol. Banderas de comparación **no persistidas** en `Graphics`: `gi_variant {A_SDFGI, B_AMBIENT_SSIL}` y `tonemap {AGX, ACES}`; `tools/environment_shots.tscn` captura las cinco variantes en la misma pose (`--variants`, `--shots-only`, `--tweak=clave=valor` en caliente). **Medido** (`render_check`, 1080p, RTX 3060, HIGH con FAST_WIDE de WP-24c): A 122 fps / p1 80 / GPU 8,03 ms (7,90 son el ojo de pez a 3 viewports; el entorno cuesta 0,96 ms más que B), B 138 / 103 / 7,07, LOW 370 fps; VRAM 2,2 GB en A y 1,4 GB en B. Capturas A/B revisadas: A · AgX conserva lectura en las sombras de la ciudad con los cian del jefe encendidos y con halo; A · ACES quema la fachada al sol (7 % de píxeles a 1,0) y desatura los cian hacia el blanco; B es más oscura y teatral pero pierde el relleno de cielo (sombras casi negras). **Recomendación: A (SDFGI) con AgX**; si el usuario quiere el contraste de B, `tonemap_agx_contrast` 1,45. Palancas si el cielo opuesto al sol (0,04) parece demasiado oscuro: `SKY_TURBIDITY` 12 → 8 o elevación del sol −6° → −10°. Traspasos: periferia quemada de las caras laterales de FAST_WIDE (WP-24c, atributos de cámara en las sub-cámaras) y `tools/enemy_showcase.tscn` fuera de calibración (WP-24d).

> **Nota de WP-24a (2026-09-20)**: los «48 fps con ciudad» de `docs/perf/2026-09-19.json` eran un **artefacto de medición** (`Engine.get_frames_per_second()` se refresca una vez por segundo; sobre ventanas cortas dio 5 fps donde el reloj de pared daba 410). Medido con reloj de pared en RTX 3060 a 1080p sin vsync, preset HIGH, jefe + 60 edificios + bot: **263–267 fps, p1 131, 3,2 ms de GPU, 367 draw calls**; LOW 407–413 fps. La ablación por rasgo (árbol en pausa) ordenó el trabajo: la viewport raíz renderizaba la escena 3D completa para no mostrar nada (con ojo de pez la FPV tiene `cull_mask = 0`) → `Viewport.disable_3d = composite.visible` en `FPVCamera` (GPU de la raíz 1,79 → 0,10 ms); SDFGI 1,24 ms; sombras 0,59; MSAA 0,44; SSAO 0,22; niebla 0,17; la oclusión es neutra pero **las `SubViewport` del ojo de pez nacían sin oclusión** y ahora la reciben junto con la escala de render y `mesh_lod_threshold`. `Graphics` aplica ahora **toda** la tabla de §3.4: sombras por preset vía `apply_sun_quality(light)` sobre el sol que cada nivel registra con `register_sun()` desde `LevelBase` (el sol de `battle_level` pasó de 700 m / 4 splits cableados a 320 m / 4 splits / SOFT_MEDIUM / fade 0,85 / `normal_bias` 1,6), `apply_environment_quality()` con SDFGI 4/5 cascadas (`cascade0` 16 m, `y_scale` 100 %), ambiente de respaldo `#2A3A52`·0,55 sin SDFGI, SSAO radio 1,2 en MEDIUM, SSIL solo ULTRA, niebla 96/128 m con froxels por preset, glow recortado en LOW, `max_emitters()` 6/8/12/12 (lo consume `VFXPool`, WP-26), y cada nivel **clona** el `Environment` en vez de mutar el `.tres`. Presets finales: MSAA off/2×/4×/8×; sombras 2048·2 splits·120 m / 4096·4·200 / 8192·4·320 / 8192·4·420 con filtro SOFT_LOW/SOFT_LOW/**SOFT_MEDIUM**/SOFT_HIGH; escala de render de las `SubViewport` 0,70/0,85/1,00/1,00; `mesh_lod_threshold` 4/2/1/1 px; ojo de pez FAST 480p / FAST 720p / **FAST 1080p** (no 720p: en 1080p desenfoca 2×; WP-24c lo cambia a FAST_WIDE) / FULL 1080p. Variante B de §3.5 medida (sin los 6 `ReflectionProbe`, que siguen sin implementar: §3.3 es de WP-24): +35 % de fps (354 vs 263), −26 % de GPU, −47 % de VRAM, imagen **más plana y lavada**; con 263 fps de margen la elección es de imagen, no de rendimiento (checkpoint 4). Recomendaciones no aplicadas por sobrar margen: MSAA del ojo de pez 4× → 2× en HIGH (ahorra 0,44 ms), degradar SDFGI (`frames_to_update_lights`, `probe_ray_count`), y en LOW la escala 0,70 se acumula con el ojo de pez a 480p (336 líneas reales): subir LOW a 720p o escala 1,0 cuesta nada con 407 fps. **WP-24c** cambió la fila «Ojo de pez» de §3.4 a `FAST 480p / FAST 720p / FAST_WIDE 1080p (laterales 720²) / FAST_WIDE 1080p (laterales 1080²)`, con FULL como opción del menú: el coste de cada `SubViewport` extra es **fijo** (SDFGI, niebla volumétrica y SSAO corren por viewport), por eso las caras laterales de FAST_WIDE llevan un `Environment` propio y barato y HIGH queda en 215 fps / p1 109 (FULL: 68 fps, p1 28, 914 draw calls); ULTRA con laterales 1080² mide 89 fps / p1 65 / 10,9 ms; `PRESET_FISHEYE_SIDE_RATIO = [2/3, 2/3, 2/3, 1,0]`; `settings_check` asevera que ningún preset use FULL y que siga siendo elegible a mano. Ver `docs/03` §1. `render_check` (§10.1) existe: 19–20 s, HIGH/variante B/LOW, capturas, SKIP limpio en headless; registrado en `run_checks.ps1` como check con ventana a 1920×1080 y como informativo en CI.

Define **cómo se ve y cómo suena** Drone Survivor: la identidad de marca y de UI (WP-25), el entorno de render y sus presets (WP-24), los efectos visuales (WP-26), el audio y la música adaptativa (WP-27), y la sacudida de cámara con el overlay FPV (WP-28).

**Incluye**

- Dirección de arte, `UIPalette` nueva con contraste verificado, tipografías bajo OFL y regeneración del tema.
- Backdrop 3D en vivo del menú principal; conservación de la tarjeta de boot del estudio "Ominoso".
- `world/environment_battle.tres`, `world/sun_dusk.tres`, `CameraAttributesPractical`, `ReflectionProbe` locales y presets LOW/MEDIUM/HIGH/ULTRA.
- Catálogo de VFX por evento con nodo, duración, pool y presupuesto.
- Distribución de buses, audio 3D, presupuesto de voces y música por 3 capas.
- `CameraRig` con modelo de trauma y `fpv_overlay.gdshader`.
- Checks `render_check`, `vfx_check`, `audio_check`, `shake_check` y capturas de menús.

**NO incluye**

- Qué dibuja cada componente del HUD ni el recorrido de menús (`docs/12`).
- Los menús de gráficos y audio en sí, ni su persistencia (`docs/04`); acá se define **qué** apaga cada preset, no la pantalla que lo elige.
- El pipeline voxel ni los materiales de los modelos (`docs/05`, `docs/10`).
- Licencias y atribuciones finales (`docs/16`), que este documento alimenta.

## 2. Dirección de arte e identidad

### 2.1 Premisa

Una ciudad voxel al anochecer, fría y azulada, con ventanas encendidas; sobre ella, colosos voxel de silueta negra con emisivos saturados (cian en visores y rodillas, naranja en respiraderos, magenta ventral). El jugador ve todo a través del video de un dron FPV: viñeta, ruido y aberración sutiles. La UI es oscura, militar y holográfica, de esquinas rectas (radio 2 px) y líneas de 1 px.

**Decisión de color de acento: ámbar.** El cian queda reservado como color **diegético**: marca lo que pertenece al enemigo y lo que se puede romper (puntos débiles, cajas de objetivo). Si la UI también fuera cian, el jugador no distinguiría "información mía" de "objetivo". El ámbar además es el hue de mayor contraste sobre un fondo casi negro (10.7:1) y arrastra la connotación de radio militar. El cian se conserva como `TARGET`, no como acento de UI.

### 2.2 `UIPalette` (propuesta)

`gui/theme/ui_palette.gd` — constantes; `ThemeBuilder` genera `main_theme.tres` a partir de ellas.

| Constante | Hex | Uso | Contraste vs `BG` |
|---|---|---|---|
| `BG` | `#0A0D10` | fondo base de pantallas | — |
| `BG_TOP` | `#0E1318` | gradiente superior del fondo | — |
| `BG_BOTTOM` | `#05070A` | gradiente inferior | — |
| `SCRIM` | `#05070ACC` | velo sobre el backdrop 3D (80 %) | — |
| `SURFACE` | `#131A20` | paneles y tarjetas | — |
| `SURFACE_ALT` | `#1A232B` | filas alternas, campos | — |
| `SURFACE_HOVER` | `#22303A` | hover y presionado | — |
| `BORDER` | `#2A3742` | bordes de 1 px | — |
| `BORDER_STRONG` | `#3E5261` | separadores y encabezados | — |
| `BORDER_FOCUS` | `#FFB020` | anillo de foco, 2 px | 10.7:1 |
| `TEXT` | `#E6EDF3` | texto principal | 16.5:1 (AAA) |
| `TEXT_DIM` | `#9FB0BE` | texto secundario | 8.8:1 (AAA) |
| `TEXT_MUTED` | `#78899A` | ayudas, unidades, deshabilitado | 5.4:1 (AA) |
| `ACCENT` | `#FFB020` | acento, valores activos | 10.7:1 (AAA) |
| `ACCENT_DIM` | `#B87A14` | acento presionado / relleno | 5.4:1 (AA) |
| `DANGER` | `#FF4D4D` | peligro, daño, derrota | 6.0:1 (AA) |
| `DANGER_DIM` | `#B03030` | relleno de barras críticas | — |
| `SUCCESS` | `#4ADE80` | confirmaciones, pilas, victoria | 11.2:1 (AAA) |
| `TARGET` | `#38E1FF` | **diegético**: puntos débiles y cajas de objetivo | 12.4:1 (AAA) |
| `SHADOW` | `#00000099` | sombras de paneles | — |
| `GRAPH_BG` | `#0C1116` | fondo del gráfico de rates | — |
| `GRAPH_GRID` | `#22303A` | rejilla | — |
| `GRAPH_AXIS` | `#5A6B78` | ejes | — |
| `GRAPH_PITCH` | `#FFB020` | curva de cabeceo | — |
| `GRAPH_ROLL` | `#38E1FF` | curva de alabeo | — |
| `GRAPH_YAW` | `#A78BFA` | curva de guiñada | — |
| `HUD_TEXT` | `#E8F4F8` | texto del HUD sobre el video | — |
| `HUD_SHADOW` | `#000000B3` | contorno de 4 px del HUD | — |
| `HUD_BOX` | `#7FE8FF` | cajas y marcos del HUD | — |
| `HUD_REC` | `#FF3B30` | punto REC | — |

Márgenes y métricas: `MARGIN_XS 4`, `MARGIN_SM 8`, `MARGIN_MD 16`, `MARGIN_LG 24`, `MARGIN_XL 40`, `RADIUS 2`, `BORDER_WIDTH 1`, `FOCUS_WIDTH 2`, `ROW_HEIGHT 44`.

Verificación de contraste: todos los colores de texto superan 4.5:1 sobre `BG` **y** sobre `SURFACE` (peor caso `TEXT_MUTED` sobre `SURFACE`: 4.9:1). El check de menús captura las pantallas para revisión visual; el cálculo de contraste se hace una vez en WP-25 con una función auxiliar en `tools/build_theme.gd` que aborta si algún par cae bajo 4.5:1.

### 2.3 Tipografías (OFL)

Tres roles, candidatas por rol. Todas SIL Open Font License 1.1 en Google Fonts; se descarga el paquete, se guarda el `LICENSE.txt` junto a los `.ttf` en `gui/theme/fonts/` y se registra en `CREDITS.md`.

| Rol | Propuesta | Alternativas | URL |
|---|---|---|---|
| Display (títulos, marca, números grandes) | **Chakra Petch** SemiBold | Rajdhani Bold, Saira Condensed | `https://fonts.google.com/specimen/Chakra+Petch` · `https://fonts.google.com/specimen/Rajdhani` |
| Texto de UI (menús, descripciones) | **Barlow Semi Condensed** Regular/Medium | Inter, IBM Plex Sans | `https://fonts.google.com/specimen/Barlow+Semi+Condensed` · `https://fonts.google.com/specimen/Inter` |
| Mono (HUD, readouts, gráficos) | **JetBrains Mono** Medium | IBM Plex Mono, Share Tech Mono | `https://fonts.google.com/specimen/JetBrains+Mono` · `https://fonts.google.com/specimen/IBM+Plex+Mono` |

Criterios: Chakra Petch tiene terminaciones cortadas y ancho angosto (aire de HUD militar) sin caer en la ilegibilidad de las fuentes "tecno"; Barlow Semi Condensed mantiene densidad en los menús de opciones, que tienen filas largas; JetBrains Mono tiene dígitos de altura x grande y 0/O y 1/l inconfundibles, que es lo único que importa en un readout. Recursive (ya presente, OFL) se conserva como respaldo si alguna de las tres falla en el import.

Tamaños base: display 44/32/24 px, texto 20/18/16 px, mono 24 px en el HUD y 18 px en los gráficos. `Theme` con *type variations* `TitleLabel`, `SubtitleLabel`, `MonoLabel`, `DangerButton`, `PrimaryButton`, `CardPanel`.

### 2.4 Regeneración del tema

`tools/build_theme.gd` sigue siendo la única fuente: lee `UIPalette`, arma `StyleBoxFlat` y `FontVariation` y escribe `gui/theme/main_theme.tres`. Nunca se edita el `.tres` a mano.

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot --script res://tools/build_theme.gd
```

El mismo script genera `hud/hud_theme.tres` (mono 24 px, contorno 4 px con `HUD_SHADOW`) y verifica los contrastes.

### 2.5 Backdrop 3D del menú principal

`gui/backdrop/menu_backdrop.tscn`:

```
MenuBackdrop (Control)
├── SubViewportContainer (stretch = true)
│   └── SubViewport (1280×720, UPDATE_ALWAYS, own_world_3d, msaa_3d = off)
│       ├── WorldEnvironment (environment_menu.tres: mismo cielo, glow sí, SDFGI no)
│       ├── Sun (DirectionalLight3D, sun_dusk.tres, sombras a 2048)
│       ├── Skyline (12–18 piezas de city/pieces, gi_mode = DISABLED)
│       ├── ColossusSilhouette (MeshInstance3D, malla de baja densidad, emisivos cian)
│       └── DriftCamera (Camera3D + Tween en bucle de 40 s, ±3 m y ±2°)
└── Scrim (ColorRect, color = SCRIM)
```

Presupuesto: ≤ 2.5 ms de GPU a 1080p. En preset LOW se reemplaza por `assets/gui/menu_backdrop_low.webp` (captura estática del mismo encuadre) y el `SubViewport` no se instancia. `MenuScreen` ya soporta fondo/backdrop: el backdrop se le pasa como escena de fondo, sin tocar su código.

### 2.6 Boot

La tarjeta de boot del estudio "Ominoso" (`gui/boot/`) se conserva **tal cual**, incluido su audio; es identidad de estudio y ya está verificada por `boot_check`. Solo se actualizan sus colores si dependen de `UIPalette`.

## 3. Entorno y luz

### 3.1 `world/environment_battle.tres`

`Environment` compartido por el nivel de batalla y por los checks de render. Valores propuestos:

| Bloque | Propiedad | Valor |
|---|---|---|
| Fondo | `background_mode` | `BG_SKY` |
| Cielo | `sky.sky_material` | `PhysicalSkyMaterial` |
| | `rayleigh_coefficient` / `rayleigh_color` | `2.4` / `#527ac7` |
| | `mie_coefficient` / `mie_eccentricity` / `mie_color` | `0.012` / `0.82` / `#f0ad6b` |
| | `turbidity` / `sun_disk_scale` | `12.0` / `1.6` |
| | `ground_color` | `#090A0D` |
| | `sky.radiance_size` / `sky.process_mode` | `RADIANCE_SIZE_256` / `PROCESS_MODE_HIGH_QUALITY` |
| Ambiente | `ambient_light_source` | `AMBIENT_SOURCE_SKY` |
| | `ambient_light_sky_contribution` / `ambient_light_energy` | `1.0` / `1.0` |
| SDFGI | `sdfgi_enabled` | `true` (HIGH/ULTRA) |
| | `sdfgi_cascades` / `sdfgi_cascade0_distance` | `5` / `16.0` m → 256 m de cobertura |
| | `sdfgi_use_occlusion` / `sdfgi_bounce_feedback` | `true` / `0.5` |
| | `sdfgi_read_sky_light` / `sdfgi_energy` | `true` / `1.0` |
| | `sdfgi_normal_bias` / `sdfgi_probe_bias` | `1.1` / `1.1` |
| | `sdfgi_y_scale` | `SDFGI_Y_SCALE_100_PERCENT` (ciudad vertical) |
| SSAO | `ssao_enabled` | `true` (MEDIUM+) |
| | `radius` / `intensity` / `power` / `detail` | `1.6` / `2.2` / `1.5` / `0.5` |
| | `horizon` / `sharpness` / `light_affect` / `ao_channel_affect` | `0.06` / `0.98` / `0.0` / `0.0` |
| SSIL | `ssil_enabled` | `false` (solo ULTRA, o fallback B de §3.5) |
| | `radius` / `intensity` / `sharpness` / `normal_rejection` | `4.0` / `1.0` / `0.98` / `1.0` |
| Niebla de profundidad | `fog_enabled` / `fog_density` | `true` / `0.0016` |
| | `fog_light_color` / `fog_light_energy` | `#6B7A9E` / `1.0` |
| | `fog_sun_scatter` / `fog_aerial_perspective` / `fog_sky_affect` | `0.25` / `0.40` / `0.30` |
| Niebla volumétrica | `volumetric_fog_enabled` | `true` (HIGH/ULTRA) |
| | `density` / `albedo` / `anisotropy` | `0.012` / `#9EA8C7` / `0.35` |
| | `length` / `detail_spread` | `96.0` (128 en ULTRA) / `2.0` |
| | `gi_inject` / `ambient_inject` / `sky_affect` | `0.6` / `0.4` / `0.35` |
| | `emission` / `emission_energy` | `#0D0F17` / `0.4` |
| | `temporal_reprojection_enabled` / `_amount` | `true` / `0.9` |
| Glow | `glow_enabled` / `glow_blend_mode` | `true` / `GLOW_BLEND_MODE_SCREEN` |
| | `glow_levels/1..7` | `0.0, 0.2, 0.8, 1.0, 0.6, 0.2, 0.0` |
| | `glow_intensity` / `glow_strength` / `glow_bloom` | `0.85` / `1.0` / `0.15` |
| | `glow_hdr_threshold` / `_scale` / `_luminance_cap` | `0.95` / `2.0` / `12.0` |
| Tonemap | `tonemap_mode` | `TONE_MAP_AGX` |
| | `tonemap_exposure` / `tonemap_white` / `tonemap_contrast` | `1.0` / `2.0` / `1.10` |
| Ajustes | `adjustment_enabled` | `true` |
| | `brightness` / `contrast` / `saturation` | `1.0` / `1.04` / `1.06` |
| | `adjustment_color_correction` | `world/lut_dusk.tres` (`Texture3D` 32³) |

Notas de Godot 4.7 que el implementador debe respetar: el glow corre **antes** del tonemap desde 4.6, así que estos valores ya están pensados para HDR; la niebla volumétrica se mezcla por transmitancia desde 4.7, y `rendering/environment/fog/use_legacy_blending` se deja en `false`.

**AgX y no ACES**: la escena está llena de emisivos muy saturados (cian de los puntos débiles, naranja de los respiraderos, trazadores). ACES desplaza el tono de esas fuentes hacia el blanco-rosado al saturarse; AgX conserva el hue mientras sube el brillo, que es exactamente lo que hace legible un punto débil brillante. ACES queda como prueba A/B en WP-24.

### 3.2 `world/sun_dusk.tres` y atributos de cámara

Un `DirectionalLight3D` no se puede guardar como `.tres`, así que `sun_dusk.tres` es un **recurso propio** `SunProfile extends Resource` que `world/sun_light.gd` (`@tool`) aplica al nodo. Así el mismo sol se comparte entre el nivel, el backdrop del menú y los checks.

| Campo de `SunProfile` | Valor | Comentario |
|---|---|---|
| `intensity_lux` / `temperature_k` | `2400.0` / `3200.0` | crepúsculo civil, luz cálida rasante; requiere `use_physical_light_units = true` |
| `angle_degrees` / `angular_distance` | `Vector3(-6, -118, 0)` / `0.6` | sol 6° sobre el horizonte, por detrás-derecha; penumbra suave |
| `shadow_enabled` / `shadow_mode` | `true` / `SHADOW_PARALLEL_4_SPLITS` | |
| `shadow_max_distance` / `shadow_split_1/2/3` | `320.0` m / `0.06`, `0.16`, `0.40` | valores de HIGH; ver presets |
| `shadow_blend_splits` / `shadow_fade_start` | `true` / `0.85` | |
| `shadow_normal_bias` / `shadow_bias` / `shadow_opacity` | `1.6` / `0.06` / `1.0` | voxels grandes: normal bias alto |

`CameraAttributesPractical` en el `WorldEnvironment`: `exposure_multiplier = 1.0`, `exposure_sensitivity = 100.0` (ISO), `auto_exposure_enabled = false` (la auto-exposición pulsa cuando el jefe llena la pantalla), `dof_blur_far_enabled = false`, `dof_blur_near_enabled = false`.

Ajustes de proyecto asociados (`docs/02`): `directional_shadow/size = 8192`, `soft_shadow_filter_quality = 3`, `use_physical_light_units = true`, `occlusion_culling = true`.

### 3.3 GI local y `gi_mode`

- `ReflectionProbe` locales, `update_mode = UPDATE_ONCE`, `box_projection = true`, `max_distance = 120`: 4 en HIGH (plaza central, avenida, azotea, calle lateral), 6 en ULTRA, 2 en MEDIUM, 0 en LOW.
- `gi_mode` por tipo de malla:

| Malla | `gi_mode` | Motivo |
|---|---|---|
| Edificios intactos y calles | `GI_MODE_STATIC` | son la fuente de rebote |
| Piezas de edificio dañado (`StageDamaged`) | `GI_MODE_STATIC` | mismo lugar, mismo aporte |
| Ruinas (`StageRubble`) | `GI_MODE_DISABLED` | la malla cambia al colapsar; lo fija `docs/10` §3.2 (riesgo 9) |
| `DebrisChunk` (rígidos) | `GI_MODE_DISABLED` | se mueven; evitan el popping de SDFGI |
| Enemigo y partes desprendidas | `GI_MODE_DISABLED` | cinemáticos y enormes |
| Dron, proyectiles, VFX | `GI_MODE_DISABLED` | irrelevantes para el rebote |

### 3.4 Presets de calidad

`Graphics` (autoload, `docs/04`) aplica el preset; este documento define **qué** cambia cada uno.

| Ajuste | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| SDFGI | off | off | on, 4 cascadas | on, 5 cascadas |
| Ambiente si SDFGI off | color `#2A3A52`, energía 0.55 | ídem | — | — |
| SSIL | off | off | off | on |
| SSAO | off | on (radio 1.2) | on | on |
| Niebla volumétrica | off | off | on (96 m) | on (128 m) |
| Niebla de profundidad | on | on | on | on |
| Glow | on, niveles 3–5 | on | on | on |
| MSAA 3D | off | 2× | 4× | 8× |
| Sombras direccionales | 2048, 2 splits, 120 m | 4096, 4 splits, 200 m | 8192, 4 splits, 320 m | 8192, 4 splits, 420 m |
| Filtro de sombra suave | 0 (duras) | 1 | 2 | 3 |
| Escala de render 3D (FSR 1.0) | 70 % | 85 % | 100 % | 100 % |
| Ojo de pez | FAST 480p | FAST 720p | **FAST_WIDE** 1080p (laterales 720²) | **FAST_WIDE** 1080p (laterales 1080²; FULL disponible en el menú) |
| `ReflectionProbe` | 0 | 2 | 4 | 6 |
| Emisores de partículas simultáneos | 6 | 8 | 12 | 12 |
| `Decal` simultáneos | 8 | 16 | 32 | 32 |
| Backdrop 3D del menú | imagen estática | vivo | vivo | vivo |
| `fpv_overlay` | solo viñeta | completo | completo | completo |

El ojo de pez FULL usa varios `SubViewport` y es el mayor costo por sí solo: por eso queda restringido a ULTRA, con `cull_mask` y `visibility_range` para no renderizar la ciudad lejana cinco veces.

### 3.5 Plan A/B de SDFGI

Riesgo 9 del plan: la ciudad cambia de forma cuando los edificios colapsan y SDFGI puede mostrar popping de iluminación indirecta.

- **Variante A (por defecto)**: SDFGI encendido, `bounce_feedback 0.5`, escombros en `GI_MODE_DISABLED`, y las transiciones de etapa de edificio reemplazan la malla **en un solo frame** para que la actualización de cascada sea una sola.
- **Variante B (respaldo)**: `sdfgi_enabled = false`, `ambient_light_source = AMBIENT_SOURCE_COLOR` con `#2A3A52` a 0.55, `ssil_enabled = true` y 6 `ReflectionProbe`.

`render_check` corre las dos y reporta fps medio, percentil 1 y draw calls de cada una; la elección definitiva la toma el usuario en el checkpoint 4 con las capturas al lado.

## 4. VFX

Todos los efectos se piden a un `VFXPool` (nodo del nivel, bajo `Pools`), que recicla por LRU y **devuelve `null` si el presupuesto está lleno** en vez de crear nodos nuevos. `GPUParticles3D` siempre con `one_shot = true`, `explosiveness = 1.0`, `fixed_fps = 30`, `interpolate = true`, `draw_order = DRAW_ORDER_VIEW_DEPTH`, `gi_mode = DISABLED`.

| Evento | Escena | Contenido | Duración | Pool | Presupuesto |
|---|---|---|---|---|---|
| Fogonazo | `vfx/muzzle_flash.tscn` | `OmniLight3D` (3 m, energía 4→0) + quad emisivo + 8 chispas | 0.06 s luz / 0.18 s partículas | fijo en el `WeaponMount` | no cuenta (1 emisor permanente) |
| Impacto en blindaje | `vfx/impact_armor.tscn` | 16 chispas + `Decal` 0.35 m | 0.35 s / decal 6 s | 12 | 1 emisor |
| Impacto en punto débil | `vfx/impact_weak.tscn` | 24 chispas `TARGET` + flash | 0.45 s | 8 | 1 emisor |
| Impacto en ciudad | `vfx/impact_city.tscn` | 20 de polvo + 6 esquirlas | 0.80 s | 8 | 1 emisor |
| Polvo de pisada | `vfx/foot_dust.tscn` | 40 planas + `FogVolume` caja de 6 m | 1.4 s | 4 (una por pata) | 1 emisor |
| Derrumbe de edificio | `vfx/collapse.tscn` | 120 partículas + `FogVolume` de 18 m | 3.0 s | 2 | 2 emisores |
| Desprendimiento de parte | `vfx/part_detach.tscn` | 30 chispas + 20 de humo | 1.2 s siguiendo al `DebrisChunk` | 4 | 2 emisores |
| Haz del láser | `vfx/laser_beam.tscn` | cilindro con `vfx/beam.gdshader` + `OmniLight3D` en el impacto + 12 chispas | vida del ataque | 2 | 1 emisor |
| Anillo de EMP | `vfx/emp_ring.tscn` | toro escalado 0→45 m por `Tween` + destello | 0.9 s | 1 | 0 emisores |
| Decal de pisotón | `vfx/stomp_decal.tscn` | `Decal` rojo de 18 m, parpadeo 4 Hz | 1.1 s telegrafía + 4 s marca | 2 | 0 emisores |
| Chispas de parte dañada | `vfx/damaged_sparks.tscn` | 12 chispas en bucle, ancladas a partes con hp < 35 % | continuo | 4 | 1 emisor c/u |

**Presupuesto duro: ≤ 12 `GPUParticles3D` emitiendo a la vez** (6 en LOW, 8 en MEDIUM). `VFXPool.active_emitters()` lo expone y `vfx_check` lo verifica cada frame.

`vfx/beam.gdshader` (`shader_type spatial`, `unshaded`, `blend_add`, `cull_disabled`): desplazamiento de UV en el eje del cilindro (`scroll_speed`), término de fresnel para engrosar el borde, pulso senoidal de intensidad y `ALPHA` por gradiente radial. Uniforms: `beam_color`, `core_color`, `scroll_speed`, `fresnel_power`, `pulse_hz`, `intensity`.

## 5. Audio

### 5.1 Buses

`default_bus_layout.tres`, 7 buses, todos enrutados a `Master`:

| Bus | dB por defecto | Contenido | Efectos |
|---|---|---|---|
| `Master` | `0.0` | — | `AudioEffectCompressor` (umbral −12 dB, ratio 4:1, ataque 20 ms, release 180 ms) → `AudioEffectLimiter` (techo −0.5 dB) |
| `Motors` | `-4.0` | motores y hélices del dron | — |
| `Weapons` | `-3.0` | disparos, impactos, sobrecalentamiento | — |
| `Enemies` | `-2.0` | servos, pisadas, telegrafías, láser | — |
| `City` | `-5.0` | derrumbes, ambiente urbano, alarmas | `AudioEffectReverb` (room 0.6, damping 0.4, wet 0.12) |
| `UI` | `-6.0` | sonidos de `UI`, boot | — |
| `Music` | `-8.0` | stems y stings | `AudioEffectLowPassFilter` (corte 600 Hz, resonancia 0.5), **deshabilitado** salvo en pausa |

El autoload `Audio` (`docs/04`) es el dueño de los volúmenes persistidos; usa `AudioServer.set_bus_volume_db(idx, linear_to_db(v))` y nunca calcula decibeles a mano. Al pausar, `PauseMenu` pide `AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), 0, true)`.

### 5.2 Audio 3D y presupuesto de voces

`AudioStreamPlayer3D` con:

| Propiedad | Valor | Nota |
|---|---|---|
| `attenuation_model` | `ATTENUATION_INVERSE_SQUARE_DISTANCE` | |
| `unit_size` | 8 m (impactos) · 24 m (servos) · 48 m (pisadas, derrumbes) | distancia a la que el volumen es 0 dB |
| `max_distance` | `600.0` para pisadas y servos; 200 para impactos | |
| `panning_strength` | `1.0` | |
| `doppler_tracking` | `DOPPLER_TRACKING_PHYSICS_STEP` en proyectiles y enemigo | |
| `area_mask` | `0` | valor por defecto en 4.7; no se usa `audio_bus_override` |

`AudioPool` (nodo del nivel) reparte un presupuesto de **24 voces** con topes por categoría: motores 4, armas 6, enemigos 6, ciudad 6, UI 2. Al pedir una voz con el tope lleno se recicla la más lejana al oyente; si empatan, la más vieja. `active_voices() -> int` lo expone para el check.

### 5.3 Música por capas

Tres stems del mismo tema, misma duración y tempo (120 BPM, 32 compases = 64 s), OGG 48 kHz estéreo:

- `ambient` — pads, ciudad dormida, sin percusión.
- `tension` — pulso grave, arpegio apagado.
- `combat` — percusión completa, metales.

Se montan en un `AudioStreamSynchronized` con `stream_count = 3` y se reproducen en un `MusicDirector extends AudioStreamPlayer` (bus `Music`). Los cruces se hacen con `AudioStreamPlaybackSynchronized.set_stream_volume(i, db)` interpolado por `Tween` en 2.5 s: los tres stems nunca se reinician, así que no hay saltos de fase ni clics.

| Situación | `ambient` | `tension` | `combat` |
|---|---|---|---|
| `INTRO` | 0 dB | −18 dB | −80 dB |
| `BATTLE`, fases `p1_siege` y `p2_alert` | −4 dB | 0 dB | −80 dB |
| `BATTLE`, fases `p3_fury`, `p4_belly`, `p5_selfdestruct` | −10 dB | −4 dB | 0 dB |
| Dron destruido / respawn | −6 dB | −10 dB | −24 dB |
| `VICTORY` / `DEFEAT` | −80 dB, con sting | −80 dB | −80 dB |

`set_phase()` recibe el `phase_id` (`StringName`) de `Events.enemy_phase_changed`, no un entero: los ids de fase son cadenas estables definidas en `docs/07`. Dentro de `BATTLE`, `set_intensity(v)` modula `tension` ±6 dB según una intensidad continua `v = f(distancia al jefe, daño recibido en los últimos 5 s)`, para que la música respire sin cambiar de capa.

Los stings de victoria y derrota son archivos aparte en un segundo `AudioStreamPlayer`; si en P3 hacen falta transiciones por compás, se migran a `AudioStreamInteractive` (4.3+), que permite `TRANSITION_TO_TIME_PREVIOUS_POSITION` para volver al punto donde quedó la capa.

### 5.4 Fuentes de sonido

1. **Sintetizados por herramienta propia** (preferido): `tools/generate_sfx.gd` headless, en la línea del `generate_ui_sounds.gd` existente, construye `AudioStreamWAV` desde `PackedByteArray` con ráfagas de ruido, ADSR y filtros. Cubre fogonazo, impactos, zumbido de servo, alarma de calor, EMP, pitidos de HUD y los loops de motor de `docs/03`. Sin licencias de terceros y regenerable.
2. **CC0** para lo que no salga bien sintetizado (derrumbes, viento urbano), con la fuente anotada en `CREDITS.md`.
3. **CC BY** solo si es imprescindible, siempre con atribución (como ya ocurre con el audio de boot). Todo esto se cierra en `docs/16` antes de publicar.

## 6. Cámara: modelo de trauma

`drone/camera_rig.gd` — `class_name CameraRig extends Node3D`, padre de la `FPVCamera`.

```gdscript
@export var max_translation: float = 0.08          # m
@export var max_rotation_degrees: float = 2.5
@export var decay_per_second: float = 1.4
@export var noise_speed: float = 22.0

func add_trauma(amount: float) -> void
func get_trauma() -> float
```

Modelo: `_trauma = maxf(_trauma - decay_per_second * delta, 0.0)`; el desplazamiento es proporcional a `_trauma * _trauma` (una sacudida chica se siente sutil y una grande, violenta). Tres muestras de un `FastNoiseLite` (`TYPE_SIMPLEX_SMOOTH`, `frequency = 0.9`, `seed = RoundManager.derive_seed("camera")`) en `(t, 0)`, `(t, 37)` y `(t, 74)` dan las tres componentes; la misma técnica se repite para la rotación. Con `trauma = 1.0` y decaimiento 1.4/s, la sacudida se extingue en 0.72 s.

Escucha `Events.camera_trauma(amount: float, position: Vector3)` (firma canónica, `docs/02` §5.1) y atenúa por distancia cuando la posición es finita: `amount * clampf(1.0 - distancia / 80.0, 0.15, 1.0)`.

Tabla de trauma. Los valores marcados con ▸ los **emite otro documento** y acá solo se registran para tener la escala completa en un solo lugar; si allá cambian, manda el otro documento.

| Evento | Trauma | Origen |
|---|---|---|
| Disparo | 0.03 (acumulable, techo efectivo ~0.25 en ráfaga) | este doc |
| Impacto recibido en el casco | 0.25 | este doc |
| ▸ `stomp` del jefe | 0.60 | `docs/07` |
| ▸ Recolocación tras `climb` | 0.50 | `docs/07` |
| ▸ Aterrizaje de `pounce` | 0.90 | `docs/07` |
| ▸ Parte rota / desprendida (`break_trauma`) | 0.35 | `docs/06` |
| ▸ Dron destruido | 1.00 | `docs/09` |
| ▸ Detonación del jefe (P5) | 1.00 | `docs/07` |
| ▸ Derrumbe de edificio | 0.65 al pasar a DAMAGED y 0.85 al pasar a RUBBLE (`low_block`: 0.45 / 0.65), dos eventos, atenuados por distancia | `docs/10` |
| Pulso EMP | 0.60 | este doc |
| Objetivo completado | 0.08 | `docs/11` |

La sacudida mueve la cámara **de verdad**, así que el horizonte del HUD en modo `camera` la sigue automáticamente: no hay dos sistemas que sincronizar.

## 7. `fpv_overlay.gdshader`

`ColorRect` full-rect con `ShaderMaterial`, dentro de un `CanvasLayer(layer = -1)` hijo del `DroneRig`: queda sobre la imagen 3D y **debajo** del `FlightHUD` (capa 0), que debe leerse siempre nítido.

```glsl
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float emp : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float noise_amount : hint_range(0.0, 0.3) = 0.035;
uniform float scanline_amount : hint_range(0.0, 0.3) = 0.06;
uniform float scanline_count = 540.0;
uniform float aberration_px = 1.2;
```

Comportamiento:

- **Base siempre activa**: viñeta radial, scanlines finas y ruido de grano. Vende el "esto es un video", no debe notarse conscientemente.
- **`damage`**: multiplica el ruido hasta ×4, tiñe los bordes hacia `DANGER`, sube la aberración cromática a 4 px y hace latir la viñeta a 1.5 Hz. Se alimenta de `Events.hull_changed(ratio)` como `1.0 - ratio`.
- **`emp`**: desplaza horizontalmente bloques de `floor(UV.y * 24.0)` filas con un desplazamiento pseudoaleatorio por bloque, desatura hasta 0.2 y agrega una barra brillante que recorre la pantalla. Se alimenta de la señal local `EnergySystem.emp_hit(glitch_seconds)` (`docs/09`) y decae 1→0 en esos segundos; es exactamente el mismo valor que usa `CombatHUD.GlitchLayer` (`docs/12`), así que el glitch del HUD y el de la imagen están en fase.
- Un solo pase, presupuesto ≤ 0.25 ms a 1080p. En preset LOW se reduce a la viñeta.

## 8. Interfaz pública

| Archivo | Clase / recurso | Notas |
|---|---|---|
| `gui/theme/ui_palette.gd` | `UIPalette` | solo `const`; sin estado |
| `gui/theme/theme_builder.gd` | `ThemeBuilder` | genera `main_theme.tres` y `hud_theme.tres` |
| `gui/backdrop/menu_backdrop.gd` | `MenuBackdrop` | `set_live(enabled: bool)` |
| `world/environment_battle.tres` | `Environment` | compartido nivel + checks |
| `world/environment_menu.tres` | `Environment` | backdrop, sin SDFGI |
| `world/sun_profile.gd` | `SunProfile extends Resource` | campos de §3.2 |
| `world/sun_light.gd` | `SunLight extends DirectionalLight3D` | `@tool`; `@export var profile: SunProfile` |
| `world/lut_dusk.tres` | `Texture3D` | corrección de color |
| `vfx/vfx_pool.gd` | `VFXPool extends Node` | ver abajo |
| `vfx/beam.gdshader` | shader espacial | haz del láser |
| `audio/audio_pool.gd` | `AudioPool extends Node` | ver abajo |
| `audio/music_director.gd` | `MusicDirector extends AudioStreamPlayer` | ver abajo |
| `drone/camera_rig.gd` | `CameraRig extends Node3D` | §6 |
| `drone/fpv_camera/fpv_overlay.gdshader` | shader de canvas | §7 |

```gdscript
# VFXPool
func request(id: StringName, xform: Transform3D, parent: Node3D = null) -> Node3D   # null si no hay presupuesto
func release(node: Node3D) -> void
func active_emitters() -> int
func budget() -> int

# AudioPool
func play_3d(stream: AudioStream, position: Vector3, category: StringName,
        volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void
func active_voices() -> int

# MusicDirector
func set_round_state(state: int) -> void
func set_phase(phase_id: StringName) -> void
func set_intensity(value: float) -> void          # 0..1
func play_sting(id: StringName) -> void
func stem_volume_db(index: int) -> float          # para el check
```

`VFXPool` y `AudioPool` escuchan el bus y traducen hechos en efectos; ningún sistema de gameplay instancia partículas ni reproduce sonidos por su cuenta. Firmas conciliadas con los documentos dueños:

| Señal | Firma | Efecto disparado |
|---|---|---|
| `shot_fired` | `(origin: Vector3, direction: Vector3)` | fogonazo, sonido en `Weapons` |
| `hit_confirmed` | `(position: Vector3, weak: bool, lethal: bool)` | `impact_armor` / `impact_weak` según `weak` |
| `enemy_part_broken` | `(enemy, part_id: StringName, position: Vector3)` | `part_detach`, chispas, trauma |
| `building_destroyed` | `(position: Vector3, value: int)` | `collapse`, trauma atenuado por distancia, destello de `CityBar` |
| `enemy_attack_telegraphed` | `(enemy, attack_id: StringName, duration: float)` | `stomp_decal`, anillo de EMP, línea guía del láser |
| `enemy_phase_changed` | `(enemy, phase_id: StringName)` | recoloreo de emisivos, cambio de stem |
| `drone_damaged` | `(amount: float, source_position: Vector3)` | chispas del dron, uniform `damage` |
| `battery_collected` | `(amount: float, position: Vector3)` | destello `SUCCESS`, sonido en `City` |
| `camera_trauma` | `(amount: float, position: Vector3)` | `CameraRig.add_trauma` con atenuación |

El `AudioRig` del enemigo (`docs/06`) reproduce sus propios servos y telegrafías con sus `AudioStreamPlayer3D`; el `AudioPool` solo le impone el bus `Enemies` y el tope de 6 voces.

## 9. Parámetros y valores iniciales

| Parámetro | Valor | Dónde |
|---|---|---|
| Acento de UI | `#FFB020` (ámbar) | `UIPalette.ACCENT` |
| Color diegético de objetivo | `#38E1FF` (cian) | `UIPalette.TARGET` |
| Contraste mínimo exigido | 4.5:1 sobre `BG` y sobre `SURFACE` | `build_theme.gd` |
| Radio de esquinas | 2 px | `ThemeBuilder` |
| Fuentes | Chakra Petch / Barlow Semi Condensed / JetBrains Mono | `gui/theme/fonts/` |
| Sol | 2400 lux, 3200 K, 6° de elevación | `sun_dusk.tres` |
| Sombras (HIGH) | 8192, 4 splits, 320 m | proyecto + `SunProfile` |
| SDFGI (HIGH) | 4 cascadas, `cascade0 = 16 m` | `environment_battle.tres` |
| Niebla volumétrica | densidad 0.012, anisotropía 0.35, 96 m | ídem |
| Glow | `SCREEN`, intensidad 0.85, umbral 0.95 | ídem |
| Tonemap | AgX, exposición 1.0, white 2.0, contraste 1.10 | ídem |
| `ReflectionProbe` | 4 en HIGH, `UPDATE_ONCE` | nivel |
| Emisores de partículas | ≤ 12 (6 LOW / 8 MEDIUM) | `VFXPool` |
| Decals | ≤ 32 | nivel |
| Voces de audio | ≤ 24 | `AudioPool` |
| Buses | `Master, Motors, Weapons, Enemies, City, UI, Music` | `default_bus_layout.tres` |
| Volúmenes por defecto | 0 / −4 / −3 / −2 / −5 / −6 / −8 dB | ídem |
| `max_distance` de pisadas y servos | 600 m | `AudioStreamPlayer3D` |
| Cruce de stems | 2.5 s | `MusicDirector` |
| Tempo y largo de stems | 120 BPM, 64 s | assets |
| Trauma: decaimiento | 1.4 /s | `CameraRig` |
| Trauma: máximos | 0.08 m y 2.5° | ídem |
| Trauma: ruido | `SIMPLEX_SMOOTH`, frecuencia 0.9, velocidad 22 | ídem |
| Overlay FPV | viñeta 0.35, ruido 0.035, scanlines 0.06, aberración 1.2 px | `fpv_overlay.gdshader` |
| Glitch de EMP | 3.0 s, 1→0 lineal | `docs/12` |
| Presupuesto de render | ≥ 60 fps a 1080p, < 900 draw calls | `render_check` |

## 10. Criterios de aceptación y checks headless

Comando base de los checks sin imagen:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn
```

Los que miden o capturan imagen **no pueden correr con `--headless`** (no hay GPU): usan `--windowed`.

### 10.1 `render_check` (WP-24)

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed --resolution 1920x1080 --path godot res://tools/render_check.tscn -- --shots=user://shots/render
```

| # | Verifica |
|---|---|
| 1 | Carga `battle_level` con `district_a` (60 edificios), el Arachnodroid y el ojo de pez en FAST, preset HIGH |
| 2 | Tras 120 frames de calentamiento, promedia 600 frames: fps medio ≥ 60 y percentil 1 ≥ 45 |
| 3 | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` máximo < 900 |
| 4 | Repite la medición con la variante B de SDFGI (§3.5) e imprime la comparación en una tabla |
| 5 | Repite con preset LOW: fps medio ≥ 120 (margen para portátiles) |
| 6 | Captura `render_high.png`, `render_low.png` y `render_sdfgi_off.png` |
| 7 | Restaura el preset de gráficos del jugador al terminar |

### 10.2 `vfx_check` (WP-26)

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/vfx_check.tscn
```

| # | Verifica |
|---|---|
| 1 | Dispara 200 pedidos al `VFXPool` en 20 s, mezclando los 11 tipos |
| 2 | `active_emitters()` nunca supera 12 (ni 8 en MEDIUM, ni 6 en LOW) |
| 3 | Todo nodo pedido vuelve al pool: el conteo de hijos del pool es estable tras 20 s |
| 4 | Sin fugas: `OBJECT_NODE_COUNT` y `OBJECT_ORPHAN_NODE_COUNT` iguales al inicio y al final (±0) |
| 5 | Con el presupuesto lleno, `request()` devuelve `null` y no crea nodos |
| 6 | Ningún `GPUParticles3D` queda `emitting = true` pasada su vida + 0.5 s |

### 10.3 `audio_check` (WP-27)

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/audio_check.tscn
```

| # | Verifica |
|---|---|
| 1 | Existen los 7 buses con el nombre exacto y todos enrutan a `Master` |
| 2 | `Master` tiene compresor y limitador; `Music` tiene un pasa-bajos deshabilitado; habilitarlo y deshabilitarlo funciona |
| 3 | 30 fuentes 3D simultáneas → `AudioPool.active_voices()` ≤ 24 y ninguna categoría supera su tope |
| 4 | Transición de stems `INTRO → BATTLE → fase 3`: cada `stem_volume_db` se mueve de forma monótona y ningún paso de 20 ms cambia más de 6 dB (sin clics) |
| 5 | Los tres stems comparten la misma posición de reproducción (±5 ms) tras 30 s |
| 6 | Restaura los volúmenes de bus del jugador al terminar |

### 10.4 `shake_check` (WP-28)

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/shake_check.tscn
```

| # | Verifica |
|---|---|
| 1 | `add_trauma(1.0)` → `get_trauma()` llega a 0.0 antes de 1.5 s (teórico 0.72 s) |
| 2 | Durante la sacudida, el desplazamiento nunca supera 0.08 m ni 2.5° |
| 3 | Al terminar, la cámara vuelve exactamente a su transformada base (error < 1e-4) |
| 4 | `Events.camera_trauma(0.5, p)` a 160 m aporta ≤ 0.5 × 0.15 |
| 5 | Con sacudida activa, `project_direction` del horizonte sigue el movimiento de la cámara: la diferencia entre el desplazamiento angular de la cámara y el del horizonte proyectado es < 1 px en los **cuatro** modos de ojo de pez (OFF, FAST, FAST_WIDE, FULL) |
| 6 | Sumar trauma 30 veces en un frame no supera 1.0 |
| 7 | La calidad de señal llega al `FlightHUD`: casco al 40 % → 0.55 y 3 barras; EMP → 0.30 y 2; las dos → 0.165 y 1; tras el respawn → 1.0 y 4 |
| 8 | Determinismo: dos rigs con la misma semilla producen la misma trayectoria (±1e-6); semillas distintas divergen |
| 9 | 30 ciclos de sacudida sin fugas de nodos ni huérfanos |
| 10 | `-- --negative` (decaimiento apagado) falla |

### 10.5 Capturas de menús (WP-25)

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed --resolution 960x540 --path godot res://tools/menu_shots_check.tscn -- --shots=user://shots/menus
```

Ocho capturas obligatorias para revisión visual: menú principal (con backdrop vivo), menú de rondas, hub de opciones, opciones de juego + HUD con preview, opciones de gráficos, opciones de audio, opciones de controles y hangar (quad + gráfico de rates). Opcionales: pausa y tarjeta de resultado. El check falla si alguna pantalla no se instancia o si queda algún `Label` con el texto igual a su clave de traducción (síntoma de clave faltante en el CSV).

## 11. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **SDFGI y ciudad cambiante** (riesgo 9 del plan): popping al colapsar edificios. Mitigado con escombros `GI_MODE_DISABLED`, reemplazo de malla en un solo frame y la variante B. Decide el usuario con `render_check` | abierto hasta el checkpoint 4 |
| 2 | **Ojo de pez FULL** (riesgo 7): varios `SubViewport` multiplican el costo. Restringido a ULTRA; si igual no llega a 60 fps, se baja su resolución interna antes que apagar SDFGI | mitigado |
| 3 | AgX vs ACES: AgX conserva el hue de los emisivos pero desatura la escena general. Si el resultado se ve lavado, la alternativa es ACES con saturación 1.12 en `adjustments` | abierto, A/B en WP-24 |
| 4 | `sun_dusk.tres` como `SunProfile` en vez de un nodo guardado: es la única forma real de tener un `.tres` de luz. Agrega un script `@tool` de 30 líneas | resuelto |
| 5 | La LUT `lut_dusk.tres` todavía no existe; hasta que se autoree, `adjustment_color_correction` va vacío y solo actúan brillo/contraste/saturación | pendiente, WP-24 |
| 6 | Los valores del `Environment` son una **propuesta de partida**: densidad de niebla, umbral de glow y cascadas de SDFGI se ajustan mirando capturas, no en abstracto | esperado |
| 7 | 24 voces puede quedar corto con 4 patas pisando, derrumbes y ráfaga sostenida. El tope por categoría existe justamente para que el arma no ahogue las telegrafías | abierto, medir en WP-23 |
| 8 | Los stems deben exportarse con exactamente el mismo largo o `AudioStreamSynchronized` desfasa; el check lo verifica a los 30 s | acordado |
| 9 | Licencias de las tres fuentes y de cualquier sonido CC0/CC BY: se registran en `CREDITS.md` y se auditan en `docs/16` antes de publicar | pendiente |
| 10 | El backdrop 3D en vivo puede tirar el fps del menú en máquinas modestas; por eso LOW usa una imagen y el `SubViewport` no se instancia siquiera | resuelto |
| 11 | `render_check` necesita GPU y no corre en el CI de GitHub por defecto; queda marcado como check local (ver `docs/15`) | acordado |
| 12 | El decal del `stomp` (18 m) y el anillo del `emp_pulse` (45 m) los pide `docs/07` como telegrafía obligatoria, no como adorno: si el `VFXPool` los descarta por presupuesto, el ataque queda sin aviso. Ambos tienen **pool dedicado y 0 emisores de partículas**, justamente para que nunca compitan por el presupuesto | resuelto |
| 13 | Los valores de trauma de `stomp`, `pounce`, `climb` y detonación los fija `docs/07` y los de rotura `docs/06`; este documento solo los tabula. Si divergen, manda el documento dueño | acordado |

## 12. Referencias cruzadas

- `02-configuracion-del-proyecto.md` — ajustes de render, sombras, unidades físicas, oclusión.
- `03-especificacion-nucleo-de-vuelo.md` — `FPVCamera`, modos de ojo de pez, audio de motores.
- `04-especificacion-configuracion-y-menus.md` — autoloads `Graphics` y `Audio`, menús que aplican los presets y los volúmenes.
- `05-pipeline-voxel.md` — emisivos de la paleta voxel que alimentan el glow.
- `09-energia-y-danio.md` — origen del uniform `damage` y de los eventos de trauma.
- `10-ciudad-destructible.md` — etapas de edificio, `DebrisPool`, derrumbes.
- `11-rondas-y-objetivos.md` — estados de ronda que dirigen la música y la cámara de intro.
- `12-interfaz-y-hud.md` — `UIPalette` aplicada al HUD, `hud_theme.tres`, `emp_strength`, pausa y filtro de música.
- `15-verificacion-y-ci.md` — qué checks corren en CI y cuáles son locales por requerir GPU.
- `16-licencias-y-atribucion.md` — OFL de las fuentes, CC0/CC BY de los sonidos, packs voxel.
