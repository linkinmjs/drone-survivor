# 07 — Arachnodroid (jefe 1)

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-19, WP-23 · Depende de: `docs/06-framework-de-enemigos.md`, `docs/05-pipeline-voxel.md`

## 1. Objetivo y alcance

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

## 4. Puntos débiles: 12 000 HP

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
| `stomp` | **1.1 s** | 0.25 s | 0.8 s | 6 s | dron | 45 dron + 55 N·s, 2 500 edificio | `CylinderShape3D` r 9 h 6 |
| `leg_sweep` | 0.9 s | 0.5 s | 1.2 s | 7 s | dron | 60 + 40 N·s | `BoxShape3D` 14×4×3 barrido |
| `head_laser` | 1.6 s | 2.0 s | 1.0 s | 9 s | dron | 8/s (120/s a edificios) | `CapsuleShape3D` r 1.2 |
| `siege_beam` | 1.8 s | 4.0 s | 1.5 s | 10 s | edificio | 700/s | `intersect_ray` + `CapsuleShape3D` r 2.5 |
| `emp_pulse` | 2.2 s | 0.3 s | 1.5 s | 25 s | dron | −25 % energía, glitch 3 s, r 45 m | `SphereShape3D` r 45 |
| `pounce` | 1.3 s | 1.2 s | **2.0 s** | 35 s | dron | 100 (letal), 2 500 edificios | `SphereShape3D` r 12 al aterrizar |
| `shake_off` | 0.8 s | 1.0 s | 0.6 s | 20 s | dron | 25 + 80 N·s | `SphereShape3D` r 16 |

Todas las consultas usan `PhysicsShapeQueryParameters3D` con `collision_mask` = capas **2** (`drone`) y **8** (`city`), cada `query_interval` 0.05 s, con el enemigo excluido. Los impulsos al dron se recortan a 120 N·s (`docs/06` §11.3).

### 5.2 `walk` — presión ambiental

Sin telegrafía: es locomoción, no acción. Cada vez que el `ProceduralLegRig` apoya un pie sobre un collider de capa 8 llama `Building.take_damage(900, plant_position)`. **Coreografía:** marcha en trote diagonal, el cuerpo se inclina según el plano de mínimos cuadrados de los pies. **VFX:** polvo por pisada, `Decal` de grieta si el apoyo fue sobre un edificio. **Audio:** pisada con sub-grave 40–70 Hz + crujido de hormigón. **Contramedida:** no hay directa; sólo romper rodillas reduce la velocidad −15 % por pata.

### 5.3 `climb` — ganar altura y aplastar

**Coreografía:** dos patas diagonales alcanzan el techo del edificio (el rayo de apoyo encuentra capa 8 por encima del `step_trigger`), el cuerpo cabecea 25° hacia arriba y el `GaitController` pasa a `TRIPOD`. **Telegrafía** (0.6 s, dos canales): anillos de hombro en ámbar + tensión de servos. **Daño:** 1 500 por apoyo sobre el edificio. **VFX:** polvo, `Decal` de grietas, caída de escombros del pool. **Contramedida:** romper la rodilla de una pata trepadora hace caer al jefe con `stagger` 1.6 s y 2 s de rodillas quietas.

### 5.4 `stomp` — castigo al dron bajo y cerca

**Telegrafía 1.1 s, tres canales:** la pata delantera del lado del dron se levanta a 1.6 × `hip_height`; un **`Decal` rojo de 18 m** se proyecta en el punto previsto, siguiendo a `believed_position` y **congelándose los últimos 0.25 s**; el anillo de la rodilla vira cian → rojo; chirrido de servo ascendente. **Activo 0.25 s:** el pie baja; `intersect_shape` con `CylinderShape3D` r 9 m h 6 m. **Daño:** 45 al casco + impulso radial 55 N·s; 2 500 a los edificios tocados. **VFX:** anillo de polvo, `Decal` de cráter, `Events.camera_trauma(0.6, punto_de_impacto)`. **Contramedida:** salir del decal antes de que termine el windup; los 0.8 s de recuperación dejan la pata estirada y la rodilla quieta.

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
| **P3 Furia** | 2 rodillas rotas **o** `weak_points_broken: [wp_head_visor]` | `unlock_attacks: [pounce]`; `cooldown ×0.74` (cadencia ×1.35); `windup ×0.85` (mínimo absoluto 0.80 s); emisivos **rojos**; `music_stem: &"combat"`; sesgo 40/60 |
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
| Puntos débiles | rodillas 1 200 / visor 1 500 / núcleos 1 900, `armor 0.0`, `damage_multiplier 3.0`, `structure_weight 1.0` |
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
