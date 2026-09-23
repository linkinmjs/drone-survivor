# 07 — Arachnodroid (jefe 1)

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-19, WP-23 · Depende de: `docs/06-framework-de-enemigos.md`, `docs/05-pipeline-voxel.md`

## 1. Objetivo y alcance

> **Nota de P2c, tanda 1 (2026-09-22, terreno irregular)**: `gait_check` suma una cuarta superficie (heightfield de ruido ±1,5 m, longitud 30 m) con los umbrales de la rampa; el rig la cruza con flotación ≤ 0,20 s, cadena nunca estirada, nunca menos de 2 patas e inclinación 3,21°. Hecho medido que queda **pendiente de decisión**: sobre relieve la planta de un pie apoyado se desplaza hasta **0,43 m** (0,00 sobre cajas), en recta, con 2° de pendiente y la cadena al 78 %: no es alcance ni giro; el objetivo del IK es el **tobillo** (`plant_position + ankle_lift`) y la planta barre un arco cuando el cuerpo cabecea para acomodar cuatro apoyos a alturas distintas. **El apoyo no resbala, el pie pivota**, y se ve. Corregirlo es apuntar el IK a la planta en `enemies/locomotion/leg.gd`, que toca las 14 métricas: se decide en el checkpoint. Mientras tanto hay una guarda de regresión en 0,50 m.

> **Nota de P2b, WP-D (2026-09-21)**: con el pueblo (92 100 HP, 59 blancos en un disco de 280 m) el bot gana en **144–166 s** de media (dos corridas), integridad 0,70, 2–4 muertes en la suite, fuego neto 115–122 s, acierto 0,49–0,51, pilas 1,55–1,83/min, ventanas de daño **2,8–3,5/min** (por primera vez cerca del objetivo ≥ 3,0 de §14: los blancos están más cerca); las cinco fases en las seis partidas (P5 a 97–164 s); 5 oros y 1 plata. **Control idle: derrota por integridad a los 511–568 s** (antes 429): el haz de asedio desperdicia daño (3 600 por uso sobre casas de 1 300) y el jefe camina más (148 `approach`). Bandas de `balance_check`: duración **90–290**, integridad **0,53–0,83**, control **420–660**; el resto igual. Palancas si el control queda largo: HP de casa 1 300 → 1 100, menos casas, `siege_beam`. §14 sigue sin cumplirse en duración humana (piso del bot 2,4–2,8 min), fuego neto y muertes.

> **Nota del checkpoint 4, segunda vuelta (2026-09-21)**: el usuario siguió encontrando el juego bastante difícil y pidió **rodillas a la mitad**: `hp` 1 600 → **800** en `tools/build_arachnodroid_profile.gd` (parte y `WeakPointProfile`; perfil regenerado, el resto byte a byte idéntico), 17 aciertos por rodilla con el arma de 16 × 3; presupuesto de puntos débiles 13 600 → **10 400** (`enemy_parts_check`). Bot, tres corridas: duración media 183–207 s (antes 259), fuego neto 108–113 s (cálculo `10 400 / (8·0,63·0,36·48)` = 119), integridad 0,74–0,80, muertes **0/1/1** (antes 5–8 en total: la partida corta da menos ventanas al `stomp` y al `pounce`; el jefe pega igual), acierto 0,51, pilas 1,7–1,8/min; fases en orden en las tres semillas, P2 dentro del primer minuto y ~70 % de la pelea en P3 o más. Rangos de `balance_check`: duración **140–340**, fuego **80–160**, integridad **0,58–0,88** (por partida), muertes **0–5 por partida y ≥ 1 en la suite** (`MIN_DEATHS_TOTAL`: la fila defiende que el dron no sea invulnerable), resto igual. **Medallas**: con `time_par` 540 s y bono 8 pts/s el bot saca 8 oros en 9 partidas (el bono de tiempo vale hasta 4 320 y una victoria de 3 min se lleva ~3 000): `time_par` quedó calibrado para una partida de 6,5–9 min que ya no existe; decisión pendiente del usuario (`docs/11` §6). §4 (rodillas 800, total 10 400), §8 (fuego neto ~119 s, 3–3,5 min de piso del bot), §12, §13 (el daño de prueba 12 de los checks del jefe es arbitrario y no cita al arma de 16) y §14 quedan corregidos por esta nota.

> **Nota del checkpoint 4 (2026-09-21)**: con el rebalance del jugador (`damage` 16, batería más larga) la partida del bot pasa de 376 a **243 s** de media (integridad 0,61 → 0,72, muertes 2/2/2 iguales: lo matan `stomp` y `pounce`, no la batería). Los rangos aseverados de `balance_check` se recalibraron con el mismo ancho: duración **190–390 s**, integridad **0,55–0,85**, fuego **110–190 s**, acierto 0,33–0,55, muertes 1–5, pilas ≤ 2,6/min. §14 y §15 #10 quedan corregidos por esta nota: el bot es un piso de la duración humana (6,3 → 4,0 min); si al usuario le queda corta, la palanca es el HP de los puntos débiles, no volver atrás el daño; la preferencia «bajar HP antes que subir daño» de §15 #10 quedó invertida por pedido del usuario. `arachnodroid_check` sigue probando el blindaje con un daño arbitrario de 12 (no cita al arma).

> **Nota del cierre de la tanda 4 (2026-09-20)**: la fila 5 de `balance_check` (acierto medio del bot sobre puntos débiles) pasa de 0,33–0,50 a **0,33–0,55**: es calibración de la tolerancia del check, no de balance. Cuatro corridas del mismo binario dieron medias 0,486, 0,490, 0,511 y 0,454, con la misma semilla 7 moviéndose 0,10 entre corridas (física no reproducible al detalle, `docs/15` §1.1); el techo de WP-23 quedó por debajo del ruido. El aviso de física por partida pasa a decir lo que mide (pico por segundo de `TIME_PHYSICS_PROCESS` con `time_scale` 4, informativo); el presupuesto de `docs/15` §5.2 se mide con `perf_report`. Pendiente menor: el título de la fila 7 sigue diciendo 240–450 s cuando `RANGE_CONTROL` es 240–480 desde WP-24d.

> **Nota de WP-29 (2026-09-20)**: la IA cuesta `fsm_state` **0,174 ms por tick** (27 % de la fase de callbacks con ciudad; 0,012 sin ciudad: el costo está en `_sync_locomotion()`, `_should_interrupt()` y el `_tick` del estado de acción en curso), `fsm_select` 0,001 y `fsm_context` < 0,001 (la capa de decisión corre a 4 Hz). El barrido de la ciudad de `EnemyFSM` se unificó en `_scan_city()` (menos trabajo, mismo resultado, `ai_check` y `balance_check` idénticos), pero **no** era el caro: no volver a optimizar ahí. Candidato P2: sub-instrumentar `fsm_state` y atacar el estado que pese.

> **Nota del cierre de WP-27 (2026-09-20)**: el haz activo suena (`laser_loop` / `siege_loop`) anclado al punto de contacto mientras dura la ventana ACTIVE, enganchado en `SweepAction` (base de las dos acciones) y no en `action_head_laser.gd`/`action_siege_beam.gd`; el pulso del EMP suma `emp_ring` a `emp_burst`; las partes bajo el 35 % chisporrotean (`sparks_loop`, 2 como mucho). Todo por el `AudioPool` dentro del tope de 6 de `enemies`; `active_voices()` del rig y `arachnodroid_check` no cambian.

> **Nota del cierre de WP-26 (2026-09-20)**: `BEAM_RADIUS` 0,6 m aplicado (r 1,2 m de daño en §5.6 intacto); luz de carga de todos los avisos a 30 000 lm y 40 m (`ai_check` y `arachnodroid_check` miden los tres canales por duración, no por lúmenes: siguen en verde); el aviso del pisotón es emisivo y su cráter quedó confirmado en fotograma.

> **Nota de WP-26 (2026-09-20)**: los avisos espaciales del `Telegraph` (§5) son ahora escenas del `VFXPool` con respaldo de malla si no hay pool: `stomp_decal` (decal rojo de 18 m con parpadeo a 4 Hz que sigue a la creencia y se congela con `freeze_zone()` los últimos 0,25 s; cráter de 4 s), `emp_ring` (toro 0→45 m con `flash_ring()` al disparar), `siege_column`, `guide_line` y `parabola` (punteada: es el efecto más legible). `SweepAction.configure_beam/update_beam/hide_beam/beam_node()` sirven `laser_beam` (cian) y `siege_beam` (ámbar-naranja) del pool; `hide_beam()` solo apaga y el pool retiene la instancia hasta `NOTIFICATION_EXIT_TREE` de la acción. `foot_dust` se dispara por `ProceduralLegRig.foot_planted` (enganchado desde `enemy_spawned`) escalado por `impact_speed`; `damaged_sparks` por `EnemyPart.damaged` bajo el 35 %. Decididos en el cierre corto: `ActionHeadLaser.BEAM_RADIUS` 0,25 → **0,6 m** (el volumen de daño de r 1,2 m de §5.6 no cambia: el usuario juzga en el checkpoint 4 si el láser se siente justo), y la `ChargeLight` del `Telegraph` (90 000 lm, 60 m) inundaba media pantalla a 30 m del pisotón y ahogaba el decal: se atenúa.

> **Nota de WP-27 (2026-09-20)**: el `AudioRig` conserva sus 6 voces + servos + carga del `Telegraph` (8 en total, `total_voices()`), pero pregunta `AudioPool.can_claim(&"enemies")` antes de tomar una voz libre y, con la categoría llena (tope 6), **recicla por prioridad** en vez de sumar; servos y telegrafías nunca se desalojan; `active_voices()` sigue midiendo el presupuesto propio de 8 que verifica `arachnodroid_check`. **Bug corregido en §10**: `generate_enemy_sounds.gd` escribía `edit/loop_mode = 1` (que en el importador es «deshabilitado») para `servo_loop`, así que el loop de servos sonaba 1,5 s y callaba; ahora es `2` (adelante), los 19 WAV son idénticos byte a byte y solo cambió `servo_loop.wav.import`. El `AudioPool` agrega la **caída** de la parte (`part_fall`, golpe a 0,35 s) como capa sobre `part_break` del rig, y no pisa los `unit_size` de 45–70 m del rig (el pool usa 24 m en su categoría `enemies`).

> **Nota de WP-24d parte 1 (2026-09-20)**: `leg_rig.tres` (horneado por `build_arachnodroid_profile.gd`): `step_duration` **0,80**, `step_trigger` **3,0**, `turn_step_trigger` 1,6, `reach_trigger` 0,95, `step_height_min` **3,5**, `stance_spread` **5,0 lateral**, `tilt_blend` **0,75**, `tilt_smooth_rate` 6,0, `body_bob` 0,02, `gait_roll` 2°, `gait_pitch` 1,5°, `gait_blend_time` 0,45, `idle_breath` 0,15 m / 0,30 Hz, `land_crouch` 0,12 / 0,30 s, `climb_pitch` 25°. Huella **de marcha** 22 × 23 m (distinta de la carcasa de 21 × 27 m de §2); rodillas a 9,4 m en marcha. §5.3 `climb`: con 22 m de huella los reposos delanteros «se abren» alrededor de un edificio angosto, así que `ActionClimb` enciende `ProceduralLegRig.set_climb_intent()` y el rig busca activamente un techo entre sus candidatos; **límite físico**: un bloque de menos de ~12 m de lado no se puede pisar por el centro y el cuerpo debe estar a menos de ~15 m de él. §5.2 `walk`: con la cadencia nueva (~1,0 apoyos/s, antes 1,8) el `crush_damage` de 900 reparte la mitad de daño por segundo a la ciudad; junto con el distrito de WP-24b, la partida de control de `balance_check` pasa a **461 s** → `RANGE_CONTROL` 240–480 (decisión del orquestador: no se subió `crush_damage`, que aceleraría también las partidas con dron, ya en rango; el equivalente sería ≈ 1 600). `arachnodroid_check`: el retroceso del escenario de `climb` baja de 18 a 12 m. `balance_check` final: 379 / 448 / 413 s, integridad 0,55–0,62, 1–3 muertes, acierto 0,46, control 461 s.

> **Nota de WP-18 (2026-09-19)**: la fila `walk` de §7 la implementa la acción de locomoción `approach` (id estable `approach`, sin telegrafía; elige el edificio objetivo con el multiplicador de fase `city_bias`). `test_stomp` fue un ataque provisional de WP-18 que WP-19 elimina al incorporar los nueve reales. Gate de apoyo de `stomp`/`leg_sweep`/`pounce`: se evalúa al entrar en `ACTIVE` y no al decidir (ver `06` §10.2 y §5.4).

> **Nota de WP-19 (2026-09-19)**: las 8 acciones (`climb`, `stomp`, `leg_sweep`, `head_laser`, `siege_beam`, `emp_pulse`, `pounce`, `shake_off`) viven en `enemies/arachnodroid/actions/` sobre `SweepAction` (tronco común del `intersect_shape`); `walk` = `approach`. `tools/build_arachnodroid_profile.gd` hornea también los `AttackProfile` y `TelegraphProfile` (`attacks/*.tres`, `attacks/telegraphs/*.tres`) desde tablas: no se editan a mano. `AudioRig` real con 19 WAV sintetizados (`tools/generate_enemy_sounds.gd`), precargados, ≤ 8 voces. Medido en `arachnodroid_check` (34 s): telegrafías exactas y con 3 canales (`climb` paga el piso de 0,80 s, no 0,6), 600 decisiones sin repeticiones tempranas, ceguera 20 s / bloqueo 30 s / respaldo 45 s, carcasa 70°, cono 55°, temporizador 45 s, física 0,65–1,36 ms/tick (mediana) caminando con 6 edificios. Ajustes respecto del texto: el decal del `stomp` mide 18 m de **diámetro** (= cilindro r 9 de la consulta); `shake_off` se centra en la cadera (14 m), no en el casco; `head_laser` gira el cuerpo durante la telegrafía (`06` §11.1); el aterrizaje del salto ya no cancela la propia acción (el bamboleo es local al rig, así existe la recuperación de 2,0 s); los multiplicadores de fase se acumulan a mano en cada fila porque `_enter_phase` reemplaza el diccionario; el pulso blanco de P5 solo encuentra 2 superficies emisivas (marcado del importador; revisar en WP-27). **Decisión de balance del orquestador (2026-09-19):** con «rodilla rota = pata entera desprendida», P2 es trípode (3 patas), P3 por rodillas es `DRAG` (2 patas, ×0,55), **P4 es un jefe postrado** (1 pata: no camina) con la carcasa abierta, y **P5 detona en el lugar** al expirar los 45 s (la marcha al centro a ×1,6 queda sin efecto). `pounce` exige 2 patas apoyadas al entrar en `ACTIVE` (embestida a rastras); `stomp`/`leg_sweep` exigen 2 además de la que actúa. Se mide en WP-23; alternativas en §15 #11.

> **Nota de WP-23 (2026-09-19)**: balance medido con `tools/balance_check` (bot `BotPilot` sobre el `battle_level` real, 3 semillas + control, `time_scale` 4, 541 s). Tres bugs corregidos antes de balancear: nadie fijaba `Perception.target` (el jefe no veía al dron; ahora `RoundManager._aim_perception()`), los tres `wp_core_*` están geométricamente **dentro** del collider de `underbelly` y eran imposibles de disparar (parche `pierces_host`, §15 #12), y el gate de apoyo hacía abortar `stomp`/`leg_sweep` (`06` §10.2). Palancas movidas: rodillas 1 200 → **1 600 HP** (total de puntos débiles 12 000 → **13 600**), cilindro del `stomp` 9×6 → **9×12 m** (puntúa hasta 12 m de altura), cápsula del `head_laser` r 1.2 → **1.8 m** (con 1.2 no tocaba al dron; con 2.5 mataba 1–5 veces), `siege_beam` 700 → **1 100/s** (saturado: el reloj de la ciudad lo marca la caminata entre torres, no el daño), `cooldown` P3/P4/P5 ×0.74 → **×0.55**. Sin tocar: asistencia de puntería, calor, `crush_damage`, colliders, pilas. Resultados (media de 3 semillas): duración **401 s** (335–515), acierto sobre débiles 0,43, ciclo de trabajo 0,61–0,66, integridad al vencer 0,61–0,63, muertes 1–2, fuego neto 208 s, 1,9–2,3 ventanas/min, `pounce` 0–1 por partida (el bot orbita a 14 m/s y `still` lo anula; contra un humano quieto saldría más); control: derrota por integridad a los 431 s. **El bot es un piso de la duración humana** (dispara el 52–56 % de la pelea sin fallar por distracción); la pasada manual del usuario decide. Rendimiento: 1,9 ms/tick con el jefe caminando, 2,1–3,8 ms en plena pelea con la ciudad (`15` §5.2, WP-24/29).

Ficha completa del **primer y único jefe del MVP**: anatomía, partes, puntos débiles, las 9 acciones con su coreografía, las 5 fases, los pesos de utilidad, la duración objetivo del combate y todos los parámetros de ajuste repartidos por `Resource`.

**Incluye:** silueta y escala; tabla de partes con HP, blindaje, función y masa de escombro; puntos débiles con exposición; las 9 acciones (telegrafía, activo, recuperación, cooldown, objetivo, daño, VFX, audio, consulta de física y contramedida); 5 fases; tabla acción × fase; cálculo de la duración; `.tres` de configuración; banco de audio; `arachnodroid_check`; el protocolo de balance de WP-23.

**NO incluye:** cómo funcionan `EnemyPart`, `WeakPoint`, el rig, la percepción y el selector — eso es `docs/06`, que este documento **aplica sin excepciones**. Tampoco el pipeline del `.vox`/GLB (`docs/05`) ni el arma del jugador (`docs/08`).

---

## 2. Silueta, escala y anatomía

Escala del pipeline: **1 voxel = 0.75 m** (`voxel_size` en `arachnodroid.parts.json`). El `.vox` es 40³ con 4 007 voxels llenos.

| Medida | Valor |
|---|---|
| Altura total en reposo | **29.25 m** (39 voxels) |
| Huella (anillo de hombros + carcasa) | **21 × 27 m** |
| Casco-caja (`hull`) | 7.5 × 16.5 × 7.5 m, entre 22 y 29 m de altura |
| Altura de cadera en marcha (`hip_height`) | **14.0 m** |
| Fémur / tibia / pie | 7.5 m / 6.0 m / 3.4 m |
| Alcance de pata estirada (`stretch_max` 1.15) | 15.5 m desde la coxa |
| Masa nominal | 900 t (sólo narrativa: el cuerpo es cinemático) |

**Lectura visual** (ver la preview de referencia): cuerpo oscuro con paneles dorados; **visor cian frontal** en el casco; **respiraderos naranjas** en la carcasa; **luz magenta ventral**; **anillos cian en las 4 rodillas**. Los emisivos del modelo original ya marcan los puntos débiles: no hay que inventar señalética, alcanza con encender y apagar la emisión.

---

## 3. Partes: jerarquía, HP, blindaje y función

Jerarquía del GLB (`docs/05` §4.4):

```
ArachnodroidRoot
└── hull
    ├── wp_head_visor · antenna_l · antenna_r · neck
    └── shoulder_ring
        ├── carapace → underbelly → wp_core_a / wp_core_b / wp_core_c
        └── leg_XX_coxa → leg_XX_femur → leg_XX_tibia → { leg_XX_foot, wp_leg_XX_knee }   (XX ∈ fl, fr, bl, br)
```

**Recuento: 31 nodos de malla** = 23 partes estructurales + 8 puntos débiles, tal como los enumera `docs/05-pipeline-voxel.md` (que adopta 31 frente a las «24» del plan y deja el número en un solo sitio: `metadata.part_count` del sidecar). **Ningún check codifica el número a mano**: `enemy_import_check` y `arachnodroid_check` lo leen del `parts.json`.

| Parte | Padre | HP | Armor | Función | Despr. | `debris_mass` | `structure_weight` |
|---|---|---|---|---|---|---|---|
| `hull` | — | 6 000 | 0.92 | `core` | no | — | **0** |
| `neck` | `hull` | 2 200 | 0.90 | `sensor` | no | — | **0** |
| `antenna_l` / `antenna_r` | `hull` | 300 | 0.55 | `cosmetic` | **sí** | 250 kg | **0** |
| `shoulder_ring` | `hull` | 5 000 | 0.92 | `core` | no | — | **0** |
| `carapace` | `shoulder_ring` | 6 400 | 0.90 | `cosmetic` | **sí** (se abre en P4) | 52 000 kg | **0** |
| `underbelly` | `carapace` | 4 000 | 0.88 | `core` | no | — | **0** |
| `leg_XX_coxa` ×4 | `shoulder_ring` | 2 600 | 0.92 | `leg` | no | — | **0** |
| `leg_XX_femur` ×4 | coxa | 2 000 | 0.88 | `leg` | **sí** | 42 000 kg | **0** |
| `leg_XX_tibia` ×4 | fémur | 1 600 | 0.88 | `leg` | **sí** | 24 000 kg | **0** |
| `leg_XX_foot` ×4 | tibia | 900 | 0.90 | `leg` | **sí** | 9 000 kg | **0** |

> **Decisión de diseño — `structure_weight = 0` en todas las partes blindadas.** Con `armor 0.90` un disparo de 12 quita 1.2 hp: derribar la carcasa a tiros exigiría ~526 000 de daño bruto, es decir, **el jugador no puede ganar disparando al blindaje**. Por eso `total_structure_ratio()` se calcula **sólo sobre los 8 puntos débiles** (12 000 HP en total): así "25 % de daño" es una magnitud medible y las fases disparan cuando deben. Las partes blindadas conservan HP para poder **desprenderse** (antenas, carcasa) y para que el cañón dé retroalimentación de impacto.

> **Apertura de la carcasa en P4 — propuesta.** `docs/05` declara una sola `carapace`, así que P4 la **rota 70°** sobre su pivote (con `Tween` de 1.2 s) en vez de desprenderla, y el núcleo ventral queda a la vista. *Alternativa* si el usuario prefiere el desprendimiento: partirla en `carapace_l` / `carapace_r` en el `parts.json` (32 nodos de malla en vez de 31) y soltarlas con 0.4 s de separación. Decisión de WP-12.

---

## 4. Puntos débiles: 13 600 HP (WP-23; el diseño original decía 12 000 con rodillas de 1 200)

Los puntos débiles son `EnemyPart` propias con **`armor = 0.0`** (por eso el disparo hace 12 × 3.0 = **36**, contra 1.2 en el blindaje) y `structure_weight = 1.0`.

| Punto débil | Hospedador | HP | Exposición | `damage_multiplier` | Al romperse (`on_destroy`) |
|---|---|---|---|---|---|
| `wp_leg_fl_knee` … `wp_leg_br_knee` (×4) | `leg_XX_tibia` | 1 200 c/u | `ALWAYS` | 3.0 | `detach_part: leg_XX_femur` → la pata entera cae; `−15 %` de velocidad; `stagger` 1.2 s |
| `wp_head_visor` | `hull` | 1 500 | `WHILE_ATTACK` | 3.0 | `blind_seconds: 20.0` (ceguera **temporal**, decisión cerrada); `lock_attacks: [head_laser]` durante `lock_seconds: 30.0`; **sensor de respaldo a los 45 s** del impacto, que devuelve la percepción nominal; chispas permanentes |
| `wp_core_a` / `b` / `c` | `underbelly` | 1 900 c/u | `AFTER_PARTS ≥ 3` **∧** `ANGLE_CONE 70°` (`cone_axis = DOWN`, `cone_half_angle 35°`) con `require_all = true` | 3.0 | 2 rotos ⇒ fase P5 |

Total: 4 × 1 200 + 1 500 + 3 × 1 900 = **12 000**.

- **Rodillas:** anillo cian encendido en todo momento. Son el único blanco válido al principio de la pelea.
- **Visor:** sólo se enciende y baja a capa 4 mientras la capa de acción está en `TELEGRAPH` o `ACTIVE`. Es la recompensa por **provocar** un ataque, sobre todo `head_laser` y `siege_beam` (4 s de ventana).
- **Núcleo ventral:** exige tres rodillas rotas **y** estar debajo, dentro de un cono de 70° de apertura. En P4 el `cone_half_angle` sube a 55° (110° de apertura) porque la carcasa ya se abrió.

---

## 5. Move set: las 9 acciones

### 5.1 Tabla resumen

| id | Telegrafía | Activo | Recup. | Cooldown | Objetivo | Daño | Consulta de física |
|---|---|---|---|---|---|---|---|
| `walk` | — | continuo | — | — | ciudad | 900 al edificio pisado | `intersect_ray` del pie (`1\|8`) |
| `climb` | 0.6 s | 2–4 s | 0.5 s | 8 s | ciudad | 1 500 por apoyo | `intersect_ray` del pie (`1\|8`) |
| `stomp` | **1.1 s** | 0.25 s | 0.8 s | 6 s | dron | 45 dron + 55 N·s, 2 500 edificio | `CylinderShape3D` r 9 h **12** (WP-23; era h 6) |
| `leg_sweep` | 0.9 s | 0.5 s | 1.2 s | 7 s | dron | 60 + 40 N·s | `BoxShape3D` 14×4×3 barrido |
| `head_laser` | 1.6 s | 2.0 s | 1.0 s | 9 s | dron | 8/s (120/s a edificios) | `CapsuleShape3D` r **1.8** (WP-23; era 1.2) |
| `siege_beam` | 1.8 s | 4.0 s | 1.5 s | 10 s | edificio | **1 100/s** (WP-23; era 700) | `intersect_ray` + `CapsuleShape3D` r 2.5 |
| `emp_pulse` | 2.2 s | 0.3 s | 1.5 s | 25 s | dron | −25 % energía, glitch 3 s, r 45 m | `SphereShape3D` r 45 |
| `pounce` | 1.3 s | 1.2 s | **2.0 s** | 35 s | dron | 100 (letal), 2 500 edificios | `SphereShape3D` r 12 al aterrizar |
| `shake_off` | 0.8 s | 1.0 s | 0.6 s | 20 s | dron | 25 + 80 N·s | `SphereShape3D` r 16 |

Todas las consultas usan `PhysicsShapeQueryParameters3D` con `collision_mask` = capas **2** (`drone`) y **8** (`city`), cada `query_interval` 0.05 s, con el enemigo excluido. Los impulsos al dron se recortan a 120 N·s (`docs/06` §11.3).

### 5.2 `walk` — presión ambiental

Sin telegrafía: es locomoción, no acción. Cada vez que el `ProceduralLegRig` apoya un pie sobre un collider de capa 8 llama `Building.take_damage(900, plant_position)`. **Coreografía:** marcha en trote diagonal, el cuerpo se inclina según el plano de mínimos cuadrados de los pies. **VFX:** polvo por pisada, `Decal` de grieta si el apoyo fue sobre un edificio. **Audio:** pisada con sub-grave 40–70 Hz + crujido de hormigón. **Contramedida:** no hay directa; sólo romper rodillas reduce la velocidad −15 % por pata.

### 5.3 `climb` — ganar altura y aplastar

**Coreografía:** dos patas diagonales alcanzan el techo del edificio (el rayo de apoyo encuentra capa 8 por encima del `step_trigger`), el cuerpo cabecea 25° hacia arriba y el `GaitController` pasa a `TRIPOD`. **Telegrafía** (0.6 s, dos canales): anillos de hombro en ámbar + tensión de servos. **Daño:** 1 500 por apoyo sobre el edificio. **VFX:** polvo, `Decal` de grietas, caída de escombros del pool. **Contramedida:** romper la rodilla de una pata trepadora hace caer al jefe con `stagger` 1.6 s y 2 s de rodillas quietas.

### 5.4 `stomp` — castigo al dron bajo y cerca

**Telegrafía 1.1 s, tres canales:** la pata delantera del lado del dron se levanta a 1.6 × `hip_height`; un **`Decal` rojo de 18 m** se proyecta en el punto previsto, siguiendo a `believed_position` y **congelándose los últimos 0.25 s**; el anillo de la rodilla vira cian → rojo; chirrido de servo ascendente. **Activo 0.25 s:** el pie baja; `intersect_shape` con `CylinderShape3D` r 9 m h 6 m. **Daño:** 45 al casco + impulso radial 55 N·s; 2 500 a los edificios tocados. **VFX:** anillo de polvo, `Decal` de cráter, `Events.camera_trauma(0.6, punto_de_impacto)`. **Contramedida:** salir del decal antes de que termine el windup; los 0.8 s de recuperación dejan la pata estirada y la rodilla quieta. **Gate de apoyo (WP-19/23):** al decidir solo se exige no estar en `LEAP`/`STAGGER`/`DOWNED`; el conteo de patas apoyadas al entrar en `ACTIVE` quedó en 0 (`MIN_SUPPORT`), porque exigir dos además de la que pisa era insatisfacible en trote (`06` §10.2).

### 5.5 `leg_sweep` — limpiar la media distancia

**Telegrafía 0.9 s:** la pata se retrae 60° (canal de **postura**), estela cian sobre la tibia, gruñido grave de servo. **Activo 0.5 s:** la tibia barre un arco de 160°; el volumen es un `BoxShape3D` de 14 × 4 × 3 m reposicionado sobre el arco cada 0.05 s. **Daño:** 60 + impulso tangencial 40 N·s. **Contramedida:** subir por encima de 18 m, o meterse **dentro** del radio de barrido (< 8 m del cuerpo), donde el arco ya pasó.

### 5.6 `head_laser` — la trampa del visor

**Telegrafía 1.6 s:** el visor carga de cian a blanco, sale una **línea guía** de 0.25 m hacia `believed_position` (con el ruido de la percepción: contra un dron en movimiento apunta mal a propósito), silbido ascendente. **Activo 2.0 s:** el haz barre hacia la posición creída a 35 °/s; `CapsuleShape3D` r 1.2 m a lo largo del haz con `damage_per_second = true`. **Daño:** 8/s al dron, 120/s a lo que toque de la ciudad. **VFX:** haz aditivo, chispas en el punto de contacto, `Decal` de quemadura. **Contramedida:** cortar la LOS detrás de un edificio, o orbitar más rápido que 35 °/s a esa distancia. **Clave:** mientras dura, `wp_head_visor` está expuesto — es el ataque que el jugador quiere provocar.

### 5.7 `siege_beam` — el reloj de la ciudad

**Telegrafía 1.8 s:** el jefe **se ancla** (las 4 patas plantadas, `lock_locomotion = true`), los respiraderos de la carcasa se abren en naranja, una **columna vertical de luz** marca el edificio elegido y el `CombatHUD` lo resalta; carga sub-grave. **Activo 4.0 s:** haz continuo al centroide del edificio, `Building.take_damage(700 * delta, punto)` → 2 800 de daño, suficiente para llevar un edificio bajo (1 200 HP) a ruinas y uno alto (3 500) a etapa `DAMAGED`. **Contramedida:** es la ventana principal para atacar — cuerpo inmóvil, rodillas expuestas y quietas durante 5.8 s; o destruir antes el edificio marcado para desperdiciar el haz (sólo reapunta tras el cooldown).

### 5.8 `emp_pulse` — castigo de proximidad media

**Telegrafía 2.2 s:** un **anillo cian de `Decal`** crece de 0 a 45 m en el suelo durante el windup, de modo que el radio se lee exactamente; la luz magenta ventral pulsa con frecuencia creciente; zumbido de condensadores. **Activo 0.3 s:** un único `intersect_shape` con `SphereShape3D` r 45 m sobre la capa 2. **Efecto:** `EnergySystem` −25 %, glitch de 3 s en el overlay FPV (`docs/13`), sin daño al casco. **Contramedida:** salir del círculo, que es visible y medible desde el segundo 0.5.

### 5.9 `pounce` — el salto letal

**Telegrafía 1.3 s:** el cuerpo se agacha al 60 % de `hip_height` (`tuck` del rig), los **cuatro anillos de rodilla arden en rojo**, una parábola guía marca el punto de caída, chillido de servo. **Activo 1.2 s:** `ProceduralLegRig.begin_leap(landing, 1.2)`, vuelo balístico. Al aterrizar: `SphereShape3D` r 12 m, **100 al dron** (letal desde casco lleno), 2 500 a los edificios del radio, `Events.camera_trauma(0.9, landing)`. **Recuperación 2.0 s:** cuerpo en altura mínima con las cuatro rodillas al alcance — **la mejor ventana de daño del combate**. **Contramedida:** desplazarse más de 14 m lateralmente durante los 1.3 s; la parábola da el punto exacto.

### 5.10 `shake_off` — antiacampe

Sólo puntúa si `time_near > 6.0 s` con el dron a < 12 m. **Telegrafía 0.8 s:** temblor de todo el cuerpo a 12 Hz con ±0.4 m de amplitud, destello blanco del anillo de hombros, traqueteo metálico. **Activo 1.0 s:** `SphereShape3D` r 16 m centrado en el casco, evaluado cada 0.05 s. **Daño:** 25 una sola vez + 80 N·s radiales hacia afuera. **Contramedida:** no acampar; o encajar el golpe y aprovechar los 0.6 s de recuperación.

---

## 6. Fases

| Fase | `when` | `then` |
|---|---|---|
| **P1 Asedio** | (base, sin condición) | ataques: `walk`, `climb`, `stomp`, `leg_sweep`, `siege_beam`. Sesgo 70 % ciudad / 30 % dron. Emisivo cian |
| **P2 Alerta** | 1 rodilla rota (`parts_broken_from` = 4 rodillas, `count 1`) **o** `structure_below: 0.75` | `unlock_attacks: [head_laser, emp_pulse]`; `walk_speed ×1.10`; sesgo 50/50; emisivo cian claro |
| **P3 Furia** | 2 rodillas rotas **o** `weak_points_broken: [wp_head_visor]` | `unlock_attacks: [pounce]`; `cooldown ×0.55` (cadencia ×1.8; WP-23, era ×0.74); `windup ×0.85` (mínimo absoluto 0.80 s); emisivos **rojos**; `music_stem: &"combat"`; sesgo 40/60 |
| **P4 Vientre** | 3 rodillas rotas | `lock_attacks: [climb]`; **la `carapace` se abre** (rotación de 70°, o desprendimiento si se adopta la variante partida); marcha `TRIPOD`; `wp_core_*` amplía el cono a `cone_half_angle 55°`; `pounce` reapunta a aterrizar **sobre** el dron con recuperación rodada; sesgo 30/70 |
| **P5 Autodestrucción** | 2 de 3 núcleos rotos (`parts_broken_from` = `wp_core_*`, `count 2`) | temporizador de **45 s** hacia el centro de la ciudad; `walk_speed ×1.6`; todos los ataques bloqueados salvo `walk` y `shake_off`; emisivo **blanco pulsante** acelerando; `defeat: true` al expirar |

**Detonación (P5).** Si el temporizador llega a 0, el jefe estalla: 25 000 de daño repartido entre los edificios a ≤ 120 m mediante `Building.take_damage`, `Events.camera_trauma(1.0, global_position)` y `Events.enemy_defeated`. El jefe **muere igual**; lo que decide victoria o derrota es la integridad de la ciudad (`docs/11`). Si el jugador rompe el tercer núcleo antes, el jefe cae sin detonar. Es el clímax: 45 s de carrera contra el reloj con el vientre abierto.

Las fases son monótonas y `defeated` se emite **una sola vez**.

---

## 7. Pesos de utilidad por fase

Multiplicadores aplicados al `score()` de cada acción antes del muestreo ponderado por `score²` entre las `top_n` 3 (`docs/06` §10). `0.0` = acción bloqueada en esa fase.

| Acción | P1 Asedio | P2 Alerta | P3 Furia | P4 Vientre | P5 Autodestr. |
|---|---|---|---|---|---|
| `walk` | 1.00 | 1.00 | 1.00 | 1.00 | **2.00** |
| `climb` | **1.20** | 0.90 | 0.60 | 0.00 | 0.00 |
| `stomp` | 0.70 | 1.00 | 1.20 | **1.40** | 0.00 |
| `leg_sweep` | 0.60 | 1.00 | 1.20 | 1.30 | 0.00 |
| `head_laser` | 0.00 | 1.10 | **1.30** | 1.10 | 0.00 |
| `siege_beam` | **1.60** | 1.00 | 0.60 | 0.40 | 0.00 |
| `emp_pulse` | 0.00 | 0.90 | 1.00 | 1.00 | 0.00 |
| `pounce` | 0.00 | 0.00 | 1.20 | **1.50** | 0.00 |
| `shake_off` | 0.80 | 1.00 | 1.20 | 1.40 | 1.40 |
| **Sesgo ciudad/dron resultante** | 70/30 | 50/50 | 40/60 | 30/70 | 100/0 |

A esto se le suma la `Personality` (±30 % por acción, fija por `Global.round_seed`): dos partidas con la misma semilla abren igual; con semillas distintas, una araña prefiere `siege_beam` y otra `climb`.

---

## 8. Duración objetivo y DPS efectivo

| Paso | Cálculo | Resultado |
|---|---|---|
| Daño bruto por segundo a punto débil | `fire_rate 8/s × damage 12 × weak_point_multiplier 3.0` | 288 /s |
| Ciclo de trabajo por calor | `heat_per_shot 0.045` → 22 disparos (2.75 s) y `overheat_lock 1.8 s` + enfriamiento | **×0.55** → 158 /s |
| Tasa de acierto realista sobre un blanco de ~3 m a 40–80 m volando | medición objetivo en WP-23 | **×0.40** → **63 /s** |
| Fuego neto necesario | `12 000 / 63` | **190 s** |
| Fracción de la pelea dedicada a disparar | esquivas, reposicionamiento, pilas cada ~90 s, respawns | 35–49 % |
| **Duración total** | `190 / 0.49` … `190 / 0.35` | **6.5 – 9 min** |

Contrapeso: la ciudad **sin oposición** cae en ~5 min (`siege_beam` 700/s × 4 s cada 10 s ≈ 280/s efectivos sobre 120 000 HP, más `walk` y `climb`). El jugador no puede quedarse quieto esquivando: la derrota por integridad < 35 % llega antes que la victoria.

Si en WP-23 la tasa de acierto real cae por debajo de 0.30, la palanca de ajuste preferida es **bajar `hp` de las rodillas a 1 000** (y recalcular los 12 000), no subir el daño del arma.

---

## 9. Locomoción, percepción y personalidad

- **Rig:** 4 patas de 3 segmentos, `GaitController` en `TROT` con pares `{FL, BR}` / `{FR, BL}`; `TRIPOD` con 3 patas (P4); `DRAG` con 2 (velocidad ×0.55); `DOWNED` irreversible con 4 patas perdidas.
- **Trepado:** el rayo de apoyo con máscara `1|8` apoya el pie en el techo del edificio y descarga `crush_damage` 900. Es el origen de la silueta más memorable del juego: el jefe subido a una torre disparando el haz de asedio.
- **Salto:** `tuck` 0.5 s → vuelo balístico 1.2 s → predicción de los 4 puntos de impacto → recolocación. Sólo lo usa `pounce`.
- **Percepción:** 10 Hz, LOS cabeza → dron con máscara `1|8`, σ = `2.0 + 0.25 · v` filtrada con τ 0.35 s, memoria 4.5 s y luego búsqueda en espiral. Romper el visor aplica `blind(20.0)` → σ ×5 y memoria 1.5 s: **un jefe ciego falla los pisotones y barre al vacío**. A los **45 s** del impacto entra en línea el sensor de respaldo y la percepción vuelve a la nominal (entre los 20 y los 45 s queda degradada).
- **Selector:** 4 Hz, `top_n` 3, `personality_spread` 0.30, semilla `Global.round_seed`.

---

## 10. Audio

Bus `Enemies`. Todo con `AudioStreamPlayer3D`, `attenuation_model = ATTENUATION_INVERSE_SQUARE_DISTANCE`, `unit_size` 45–70 según el evento (el jefe se oye desde 150 m).

| Evento | Diseño | Disparo |
|---|---|---|
| `footstep` | impacto 40–70 Hz + crujido de hormigón, 4 variantes alternadas | `ProceduralLegRig.foot_planted` (volumen por `impact_speed`) |
| `servo_loop` | loop de motor filtrado; pitch y volumen modulados por `AudioRig.set_servo_load()` | continuo mientras la velocidad angular > 2 °/s |
| `laser_charge` | barrido 200 → 1 800 Hz durante 1.6 s | entrada en `TELEGRAPH` de `head_laser` |
| `siege_charge` | sub-grave 35 Hz con armónico creciente, 1.8 s | `TELEGRAPH` de `siege_beam` |
| `emp_charge` / `emp_burst` | zumbido de condensadores 2.2 s → impulso + cola de ruido filtrado | `emp_pulse` |
| `leg_tear` | desgarro metálico 0.8 s + **chillido** agudo + impacto sub | `WeakPoint.destroyed` de una rodilla |
| `part_break` | fractura corta | cualquier `Events.enemy_part_broken` |
| `phase_shift` | acorde descendente + respiración de servos | `Events.enemy_phase_changed` |
| `selfdestruct_tick` | pulso acelerando de 1 Hz a 6 Hz | P5, sincronizado con el emisivo blanco |

---

## 11. Interfaz pública

El Arachnodroid **no agrega clases nuevas**: es configuración del framework más un `EnemyAction` por ataque.

```
enemies/arachnodroid/
├── arachnodroid.tscn          # árbol estándar de docs/06 §2
├── arachnodroid.glb           # + arachnodroid.parts.json (docs/05)
├── arachnodroid.gd            # extends EnemyBase; sólo cablea el temporizador de P5
├── profiles/
│   ├── arachnodroid_profile.tres   (EnemyProfile)
│   ├── leg_rig.tres                (LegRigProfile)
│   ├── perception.tres             (PerceptionProfile)
│   └── parts/*.tres                (EnemyPartProfile de override) · weak_points/*.tres
└── attacks/
    ├── walk.tres · climb.tres · stomp.tres · leg_sweep.tres · head_laser.tres
    └── siege_beam.tres · emp_pulse.tres · pounce.tres · shake_off.tres   (AttackProfile)
```

```gdscript
class_name Arachnodroid extends EnemyBase
signal selfdestruct_started(seconds: float)
signal selfdestruct_tick(remaining: float)
func selfdestruct_remaining() -> float      # -1.0 si P5 no empezó
func detonate() -> void                     # daño masivo a ≤ 120 m + defeated
```

**Capas de física usadas** (`docs/02` §3.1): partes blindadas en **3** (`enemy_body`, máscara 1·2·8·9); puntos débiles expuestos en **4** (`enemy_weak`, máscara 1·2); escombros en **9** (`debris`, máscara 1·2·8·9); rayos de pie y de LOS con máscara `1|8`; barridos de ataque con `intersect_shape` sobre las capas **2** y **8**. Ningún `Area3D`.

**Claves de traducción:** `ENEMY_ARACHNODROID`; `ATK_STOMP`, `ATK_LEG_SWEEP`, `ATK_HEAD_LASER`, `ATK_SIEGE_BEAM`, `ATK_EMP_PULSE`, `ATK_POUNCE`, `ATK_SHAKE_OFF`, `ATK_CLIMB`; `WP_KNEE`, `WP_VISOR`, `WP_CORE`; `BOSS_PHASE_1…5`.

**Registro:** `EnemyCatalog.ENTRIES[&"arachnodroid"] = {"scene": …, "profile": …, "display_key": "ENEMY_ARACHNODROID"}`.

---

## 12. Parámetros y valores iniciales por `Resource`

| Archivo | Parámetros |
|---|---|
| `profiles/arachnodroid_profile.tres` | `walk_speed 6.0` · `turn_rate 25.0` °/s · `hip_height 14.0` · `max_step_per_tick 0.6` · `armor_default 0.90` · `stagger_seconds 0.9` (1.2 al perder pata) · `leg_speed_penalty 0.15` · `downed_legs_lost 4` · `debris_lifetime 20.0` · `decision_hz 4.0` · `top_n 3` · `personality_spread 0.30` |
| `profiles/leg_rig.tres` | `step_duration 0.55` · `step_trigger 3.5` · `step_height_min 3.0` · `step_height_bias 2.0` · `stretch_max 1.15` · `tilt_blend 0.6` · suavizados `4.0` s⁻¹ · `foot_ray_span 40.0` con máscara `1\|8` · `crush_damage 900` · `leap_tuck_time 0.5` · `gait_pairs [[FL,BR],[FR,BL]]` · `tripod_min_planted 2` |
| `profiles/perception.tres` | `perception_hz 10` · `noise_base 2.0` · `noise_speed_factor 0.25` · `filter_tau 0.35` · `memory_seconds 4.5` · `blind_noise_factor 5.0` · `blind_memory_seconds 1.5` · `head_part_id &"hull"` · `search_radius_max 45.0` |
| `attacks/*.tres` | ventanas, cooldowns, daños e impulsos de la tabla §5.1; `query_interval 0.05`; `query_layers` capas 2 y 8; `TelegraphProfile` por ataque |
| Puntos débiles | rodillas 800 / visor 1 500 / núcleos 1 900, `armor 0.0`, `damage_multiplier 3.0`, `structure_weight 1.0` |
| Escombros | antena 250 kg · pie 9 t · tibia 24 t · carcasa 52 t · fémur 42 t; `continuous_cd` en todo lo > 4 m |

---

## 13. Criterios de aceptación y `arachnodroid_check`

`"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/arachnodroid_check.tscn`

Sale **0** al pasar todo, **1** con `FAIL: <criterio> esperado=<x> medido=<y>`, **2** si falta un recurso. Restaura `Global.round_seed` y la configuración al salir. El jefe se instancia sobre un suelo sintético con 6 edificios de prueba y un dron simulado (`Node3D` movido por script); **nunca** se abren escenas de juego reales.

| # | Criterio | Umbral |
|---|---|---|
| 1 | Construcción: tantas partes como declara `metadata.part_count` (31: 23 estructurales + 8 puntos débiles), jerarquía igual a `parts.json` | igualdad exacta de ids |
| 2 | Daño: 12 al `hull` (`armor 0.92`) y 36 a una rodilla (`armor 0.0`, ×3.0) | 0.96 y 36.0 ± 0.01 |
| 3 | **Las 5 fases se alcanzan aplicando daño programático en orden** (1 rodilla → 2 rodillas → 3 rodillas → 2 núcleos) | 5 `Events.enemy_phase_changed` con los ids `p1_siege…p5_selfdestruct`, sin retrocesos |
| 4 | Desbloqueos por fase | `head_laser`/`emp_pulse` sólo desde P2; `pounce` sólo desde P3; `climb` bloqueado en P4 |
| 5 | Exposición del núcleo | no expuesto con 2 rodillas rotas; expuesto con 3 rodillas **y** el dron dentro del cono de 70° por debajo |
| 6 | Exposición del visor | capa 4 sólo mientras la acción está en `TELEGRAPH`/`ACTIVE`; capa 3 el resto |
| 7 | **Cada ataque emite telegrafía ≥ 0.8 s** en las 5 fases, con ≥ 2 canales (3 en `pounce`) | `enemy_attack_telegraphed` con `duration >= 0.80` |
| 8 | **Cooldowns respetados** en 600 decisiones simuladas | 0 repeticiones antes del `cooldown` efectivo de la fase |
| 9 | **`defeated` se emite una sola vez** (por 3 núcleos y por expiración del temporizador, en dos corridas) | exactamente 1 emisión por corrida |
| 10 | **La pérdida de 4 patas deja al enemigo en `DOWNED`** | `is_downed() == true`, `locomotion_state() == &"DOWNED"`, velocidad 0 |
| 11 | Efectos de `on_destroy` | romper una rodilla desprende su fémur; romper el visor da `is_blinded()` 20 s, `head_laser` bloqueado 30 s y percepción nominal restituida a los 45 s |
| 12 | P5 | temporizador 45.0 s ± 0.1; `detonate()` daña a ≤ 120 m y emite `enemy_defeated` |
| 13 | Escombros | `DebrisPool.get_live_count() <= 24` con las 4 patas, la carcasa y las 2 antenas desprendidas |
| 14 | Rendimiento | física < 2.0 ms/tick con el jefe caminando y 6 edificios |
| 15 | **Haces visibles** (agregado al cerrar WP-19): `head_laser` y `siege_beam` muestran su haz placeholder (`SweepAction.configure_beam/update_beam/hide_beam`, `CylinderMesh` aditivo hasta el `contact_point`) en algún tick de `ACTIVE`, en ninguno de `TELEGRAPH`/`RECOVER`, y quedan apagados al cerrar el ciclo; las otras seis acciones no tienen nodo de haz | exacto |

---

## 14. WP-23 — balance y smoke test manual

Tres partidas manuales completas de 6–10 min con la radio del usuario, registrando con `perf_report` y un log de `Events`:

| Métrica | Objetivo | Palanca si falla |
|---|---|---|
| Duración total del combate | 6.5 – 9 min | `hp` de rodillas (1 200 → 1 000/1 400) |
| Tasa de acierto real sobre puntos débiles | ≥ 0.35 | `aim_assist_strength`, tamaño del collider del punto débil |
| Ciclo de trabajo efectivo del arma | 0.50 – 0.60 | `heat_cooldown`, `overheat_lock` |
| Integridad de la ciudad al vencer | 45 – 70 % | peso de `siege_beam` en P1, `crush_damage` |
| Muertes del dron por partida | 1 – 3 | daño de `stomp`/`pounce`, radio de los decals |
| Segundos de fuego neto | 170 – 210 s | confirma el cálculo de §8 |
| Ventanas de daño por minuto (recuperaciones de `pounce`/`siege_beam`) | ≥ 3 | cooldowns de P3 |
| Legibilidad de telegrafías (aciertos del jugador en esquivar) | ≥ 70 % | duración y contraste del `Decal` |
| Reintentos hasta la primera victoria | 2 – 4 | balance global |

Se acepta WP-23 cuando las tres partidas caen dentro de los rangos y la partida de control (ignorar al jefe 5 min) termina en derrota por integridad < 35 %.

**Resultado automático de WP-23 (`tools/balance_check`, 2026-09-19).** Rangos aseverados por el check sobre la media de las tres semillas (la física de Jolt no es reproducible entre corridas, `15` §1.1): duración 340–540 s (medido 401), integridad al vencer 0,45–0,70 (0,61–0,63), muertes 1–5 con media ≥ 1 (1, 1, 2), fuego neto 170–250 s (208), acierto 0,33–0,55 (0,43; techo subido en el cierre de la tanda 4), ventanas ≥ 1,5/min (1,9–2,3: el objetivo de ≥ 3 es aritméticamente inalcanzable, §15 #13), control en derrota por integridad en 240–450 s (431), física mediana bajo la guarda de regresión, `time_scale` restaurado, y prueba negativa (bot sin esquiva y σ 25°: acierto 0,02, pierde). El ciclo de trabajo del arma real es 0,61–0,66 (no 0,55: `default_gun.tres` da 22 disparos en 2,75 s + 1,8 s de bloqueo). Las tres partidas manuales del usuario siguen siendo la aceptación final.

---

## 15. Riesgos y decisiones abiertas

| # | Riesgo / decisión | Mitigación o pendiente |
|---|---|---|
| 1 | Con 29 m de altura y patas de 15 m, el dron puede quedar **debajo** y no ver ningún punto débil | las rodillas están a 6–12 m: alcanzables desde abajo y de costado; el `CombatHUD` marca la más cercana |
| 2 | `siege_beam` ancla al jefe 5.8 s: puede sentirse un maniquí | el peso cae de 1.60 a 0.40 entre P1 y P4; en P3 la cadencia ×1.35 lo compensa |
| 3 | Si se adopta la variante de carcasa partida, soltar 2 × 26 t en el mismo tick satura el pool | se sueltan con 0.4 s de separación y `continuous_cd`; la rotación de 70° evita el problema por completo |
| 4 | El temporizador de P5 puede resultar frustrante si el dron acaba de morir | el respawn es de 12 s y el temporizador **no se pausa**: es intencional, se evalúa en WP-23 |
| 5 | **Propuesta:** apertura de la carcasa en P4 por rotación de 70° (variante: partirla en dos mitades desprendibles) | confirmar con `docs/05` en WP-12 |
| 6 | **Propuesta:** `structure_weight = 0` en el blindaje | si se quiere que la carcasa contribuya, habría que rebalancear todos los `structure_below` de §6 |
| 7 | Duración de la ceguera del visor | **Cerrado (2026-09-19)**: temporal, 20 s (`on_destroy.blind_seconds`) con sensor de respaldo a los 45 s. Si en WP-23 el visor resulta trivial de romper, subir su HP antes que la duración |
| 8 | **Abierto:** daño de `head_laser` a la ciudad (120/s) | puede volverlo un segundo `siege_beam` sin querer; medir en WP-23 |
| 9 | **Abierto:** `pounce` con cooldown 35 s podría no aparecer nunca en peleas cortas | si en 3 partidas sale < 2 veces, bajar a 28 s |
| 10 | Coreografías dependientes del rig (`stomp`, `leg_sweep`, `pounce`) | WP-19 sólo empieza con `gait_check` en verde (WP-17) |
| 11 | **Decidido (WP-19/23, 2026-09-19):** con la pérdida de la pata entera por rodilla, en P4 queda una sola pata (nada de trípode) y el jefe no camina; P5 detona en el lugar; `pounce` con ≥ 1 apoyo. WP-23 midió además que con la **cuarta** rodilla rota el jefe entraba en `DOWNED`, el cuerpo se hundía a y = −12,3, los núcleos no se exponían y **la ronda no terminaba nunca** → **estado final de DOWNED (WP-19b)**: el cuerpo descansa sobre el suelo (origen a suelo − 6 m, núcleos a ~6,5 m), los tres núcleos quedan expuestos permanentemente, y si P5 no había empezado arranca con un temporizador propio de **90 s**; la ronda siempre termina. Alternativas para P2/P3: muñón de fémur usable, marcha `CRAWL` | cerrado para el MVP |
| 12 | **Abierto (WP-23):** las cajas de `wp_core_a/b/c` (y ∈ [12,5, 14,0], x ∈ ±1,5, z ⊂ ±2,25) están contenidas en las tres dimensiones dentro de `underbelly` (y ∈ [6,5, 14,0], x ±9,75, z ±6,0): ningún disparo llega. Parche vigente: `pierces_host` apaga la capa de la panza mientras un núcleo está expuesto. Arreglo real: sacar las cajas de los núcleos por debajo de la cara inferior de la panza en `arachnodroid.parts.json` (`05`) | P2 (WP-24 o WP-12 bis) |
| 13 | **Cerrado (WP-23):** «≥ 3 ventanas de daño por minuto» de §14 es inalcanzable: con el enfriamiento de P3 en ×0,55 el ciclo mínimo del haz es 12,8 s (4,7/min) y el del salto 28,7 s (2,1/min), y solo si el jefe no hiciera nada más. Medido 1,9–2,3; el check exige ≥ 1,5 | aceptado |
| 14 | **Cerrado (WP-23):** el control (ignorar al jefe) pierde a los 431 s y no a los 300: el daño está saturado (23 ráfagas de asedio reparten 101 000 contra los 78 000 necesarios, un tercio cae sobre ruinas); el reloj lo marca la caminata entre torres. Palancas si se quiere acelerar: `walk_speed` o menos HP de distrito | aceptado (240–450 s) |

---

## 16. Referencias cruzadas

- `docs/05-pipeline-voxel.md` — `arachnodroid.parts.json`, GLB, colisionadores y metadatos por parte.
- `docs/06-framework-de-enemigos.md` — todas las clases, recursos y reglas que este documento configura.
- `docs/08-combate-y-armas.md` — `WeaponProfile` (8/s, 12, ×3.0) del que sale el DPS de §8.
- `docs/09-energia-y-danio.md` — casco 100, drenaje de `emp_pulse`, respawn 12 s.
- `docs/10-ciudad-destructible.md` — `Building.take_damage(amount, point)` que usan `walk`, `climb`, `siege_beam`, `stomp`, `pounce` y la detonación de P5.
- `docs/11-rondas-y-objetivos.md` — la ronda 1 lo instancia desde `EnemyCatalog` y escucha `enemy_defeated`.
- `docs/12-interfaz-y-hud.md` — barra de jefe por partes, aviso de telegrafía, marcador del edificio de `siege_beam`.
- `docs/13-identidad-visual-y-audio.md` — emisivos, haces, polvo, glitch del EMP, stem `combat`.
- `docs/15-verificacion-y-ci.md` — `arachnodroid_check` y el smoke test manual del MVP.
