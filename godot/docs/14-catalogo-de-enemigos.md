# 14 — Catálogo de enemigos

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: P3 (WP-31…WP-39) · Depende de: `docs/06-framework-de-enemigos.md`, `docs/05-pipeline-voxel.md`, `docs/07-arachnodroid.md`

## 1. Objetivo y alcance

Ficha de producción de los **9 assets voxel** del juego: qué es cada uno, a qué escala se instancia, cómo se mueve, qué hace contra la ciudad y contra el dron, dónde se le pega, qué personalidad tiene, en cuántas fases se rompe, cuánto cuesta implementarlo y cómo se ve su `parts.json`. Cierra con el **orden de producción**, la **tecnología nueva** que introduce cada uno y las **rondas** que habilita.

**Incluye:** las 9 fichas; escala propuesta en metros para cada `.vox`; ataques con telegrafía; puntos débiles y partes desprendibles; personalidades; fases sugeridas; riesgos de segmentación e implementación; bocetos de `parts.json`; orden de producción justificado; tabla de tecnología nueva; mapa de rondas.

**NO incluye:** las clases del framework (`docs/06`), que P3 **extiende pero no reescribe**; la ficha detallada del Arachnodroid (`docs/07`), que acá aparece sólo como referencia de escala; el formato del `parts.json` ni el mesher (`docs/05`); la definición de las rondas (`docs/11`).

**Todos los valores numéricos de este documento son propuestas de partida**: se ajustan en el WP de cada enemigo con su check y una sesión de juego, igual que el Arachnodroid en WP-23.

---

## 2. Escala y convenciones comunes

Los `.vox` están en `godot/assets/_raw/<Enemy>.zip`, **solo lectura**: se listan con `unzip -l` y se extraen **fuera del repo**. El único `.rar` es `Mecha01.rar`, que se lista y extrae con `"C:\Program Files\WinRAR\UnRAR.exe" x <archivo> <destino fuera del repo>` (disponible en la máquina de desarrollo). En todos ellos el eje **Z del `.vox` es la altura**; el `axis_map` del sidecar es `{x:+x, y:+z, z:-y}` como en el Arachnodroid.

| # | Enemigo | `.vox` (X×Y×Z) | Voxels | `voxel_size` propuesto | Altura | Huella |
|---|---|---|---|---|---|---|
| 1 | Arachnodroid | 40×40×40 | 4 007 | **0.75** (fijado en `docs/07`) | 29.3 m | 21 × 27 m |
| 2 | QuadrupedTank | 38×50×56 | 28 400 | **0.42** | 23.5 m | 16 × 21 m |
| 3 | MechGolem | 52×40×54 | 17 600 | **0.50** | 27.0 m | 26 × 20 m |
| 4 | MechaTrooper | 52×32×60 | 21 400 | **0.36** | 21.6 m | 18.7 × 11.5 m |
| 5 | FieldFighter | 38×16×59 | 3 600 | **0.55** | **32.5 m** | 20.9 × 8.8 m |
| 6 | MobileStorageBot | 50×34×46 | 17 200 | **0.30** | 13.8 m | 15 × 10.2 m |
| 7 | Mecha01 | 38×40×44 | (RAR) | **0.45** | 19.8 m | 17.1 × 18 m |
| 8 | ReconBot | 27×28×59 | 10 400 | **0.20** | **11.8 m** | 5.4 × 5.6 m |
| 9 | Companion-bot | 23×18×57 | 2 700 | **0.28** | 16.0 m | 6.4 × 5.0 m |

**Lectura de escala:** el rango va de 11.8 m (ReconBot, apenas el doble de un piso) a 32.5 m (FieldFighter, el más alto del juego). El jefe final **no es el más grande a propósito**: el Companion-bot es el cerebro, no el músculo.

Convenciones que hereda todo enemigo nuevo (§13 de `docs/06`): ids estables en `EnemyCatalog`; claves `ENEMY_*`, `ATK_*` y `WP_*` en `localization/translations.csv`; blindaje 0.90 y `structure_weight 0` en partes estructurales, `armor 0.0` y `structure_weight 1.0` en puntos débiles; **telegrafía ≥ 0.9 s** (0.8 s absoluto); ningún `Area3D`; un check headless por enemigo.

---

## 3. Fichas

### 3.1 Arachnodroid — coloso asediador *(referencia, ya producido en WP-19)*

Cuadrúpedo insectoide de 29.3 m, cuerpo oscuro con paneles dorados, visor cian, respiraderos naranjas, luz magenta ventral y anillos cian en las rodillas. Define el `ProceduralLegRig`, el desprendimiento de partes y las 5 fases. Ficha completa en **`docs/07-arachnodroid.md`**. Presupuesto de HP de puntos débiles: 12 000.

---

### 3.2 QuadrupedTank — artillería de asedio *(WP-31)*

**Visual.** Bloque acorazado verde camuflaje sobre cuatro patas cortas y gruesas. El frente lo domina una **franja naranja incandescente** horizontal, como la boca de un horno; arriba a un lado, una torreta con cañón corto y un **reflector azul** muy brillante; atrás, una escalera de servicio y paneles oscuros. Lee como maquinaria de guerra pesada, no como un bicho.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Artillería · cuadrúpedo lento que **se ancla** para disparar |
| Reuso | **90 %** del `ProceduralLegRig` (patas cortas: `hip_height` 9 m, `step_trigger` 2.2 m) |
| Personalidad | Defensiva; castiga el estatismo del dron; evita la corta distancia |
| Dificultad / riesgo | **M** · **28 400 voxels**: es el modelo más denso del pack. La segmentación necesita muchas cajas y `exclude`; `--report` debe dar 0 `_unassigned` y el presupuesto de triángulos puede exigir dividir por material |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `mortar_barrage` | ciudad | 2.0 s | la torreta se eleva 40°, la franja naranja late; 3 salvas balísticas con `Decal` de impacto previsto en el suelo; los proyectiles son `RigidBody3D` en capa 6 |
| `demolition_shell` | ciudad | 1.5 s | láser de puntería del reflector sobre la fachada; disparo directo, 3 000 al edificio |
| `deploy_anchor` | propio | 0.8 s | clava las 4 patas, `lock_locomotion`; +40 % de daño y −50 % de dispersión mientras dure |
| `flak_curtain` | dron | 1.2 s | destellos de carga en la culata; ráfaga **predictiva** sobre `believed_position + believed_velocity · t_vuelo`; `intersect_shape` esférico r 8 por estallido |
| `searchlight_lock` | dron | 1.0 s | el foco azul te persigue; si te sostiene 2 s, el `flak` gana +30 % de precisión y el `CombatHUD` avisa |

**Puntos débiles:** franja naranja del respiradero (`ALWAYS`, cubierta por los escudos laterales hasta romperlos), culata del cañón (`WHILE_ATTACK`), 4 actuadores de pata (`ALWAYS`). **Desprendibles:** cañón, escudos laterales, reflector, patas.

**Fases (3):** P1 Móvil (avanza y bombardea) → P2 Anclado (escudos desplegados, `barrage` + `flak`; pierde movilidad, gana potencia) → P3 Desesperado (escudos rotos, cañón directo, marcha con 3 patas).

**Boceto de `parts.json`:** `chassis`(root) → `turret_ring` → {`cannon_barrel`(detachable), `wp_cannon_breech`}; `wp_vent_strip_f/l/r`; `shield_l/r`(detachable); `searchlight`(detachable, `sensor`); `ladder`(cosmetic); por pata `leg_XX_hip`(leg_root) → `thigh`(leg_segment, detachable) → `shin`(leg_segment) → {`foot`(foot), `wp_leg_XX_actuator`}.

---

### 3.3 MechGolem — bruto bípedo *(WP-32)*

**Visual.** Bípedo rojo óxido de hombros enormes y planos que forman una visera sobre el cuerpo, con **propulsores blanco-azulados** encendidos en la parte superior. Brazos gruesos colgando casi hasta el suelo, **brasa naranja** en la cintura, piernas cortas y macizas, sin cabeza visible. Lee como un gorila industrial.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Bruto de cuerpo a cuerpo · **bípedo nuevo (`BipedRig`)** + dash con propulsores |
| Reuso | IK de dos huesos, `Perception`, `UtilitySelector`, partes y escombros. **El `GaitController` de pares diagonales NO sirve** |
| Personalidad | Persecución; se enfurece al perder un brazo; ignora la ciudad si tiene LOS del dron |
| Dificultad / riesgo | **L** · el `BipedRig` es el mayor salto técnico de P3: equilibrio sobre 2 apoyos (modelo de péndulo invertido), paso alterno, balanceo de brazos y recuperación de tropiezo |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `haymaker` | ciudad | 1.2 s | retrae el brazo, hombro encendido; puñetazo a la fachada, 2 800 al edificio |
| `building_throw` | ciudad | 2.4 s | agarra un edificio en etapa `DAMAGED`, se yergue con los propulsores al máximo y lo **lanza**: el proyectil es un `RigidBody3D` real de capa 6 |
| `swat` | dron | 0.9 s | manotazo en cono de 120°, `BoxShape3D` barrido; 55 + 50 N·s |
| `shockwave` | dron + ciudad | 1.4 s | los dos puños al suelo; **`Decal` anular** que crece hasta 26 m; 40 + 90 N·s y 900 a los edificios del anillo |
| `thruster_dash` | dron | 1.0 s | los propulsores dorsales se encienden al blanco (y quedan **expuestos**); embestida de 35 m en 0.7 s |

**Puntos débiles:** placas de hombro ×2 (`ALWAYS`), propulsores dorsales (`WHILE_ATTACK`, sólo durante el dash), núcleo de pecho (`AFTER_PARTS` ≥ 2 = ambos brazos). **Desprendibles:** **brazos** (cambian el move set), placas de hombro.

**Fases (4):** P1 Demoledor → P2 Propulsado (desbloquea `thruster_dash`) → P3 Manco (1 brazo: sin `building_throw`, +cadencia) → P4 Desarmado (sin brazos: sólo embestidas y onda; **núcleo de pecho expuesto**).

**Boceto de `parts.json`:** `pelvis`(root) → `torso` → {`shoulder_plate_l/r`(weak_point, detachable), `wp_thruster_l/r`, `wp_chest_core`, `arm_l/r_upper`(detachable) → `forearm` → `fist`}; `leg_l/r_thigh`(leg_root) → `shin`(leg_segment) → `foot`(foot).

---

### 3.4 MechaTrooper — soldado a distancia *(WP-33)*

**Visual.** Bípedo verde oliva militar, cabeza-caja con **visera naranja** encendida, grandes pods de hombro con rejillas naranjas, un **brazo-gatling** largo a la derecha, mochila de munición, piernas digitígradas con marcas rojas. Lee como infantería mecanizada.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Soldado de fuego sostenido · bípedo que **usa cobertura** |
| Reuso | **95 % del `BipedRig`** del MechGolem (proporciones más esbeltas) |
| Personalidad | Metódico; se reposiciona detrás de edificios cuando no tiene LOS; nunca avanza en campo abierto |
| Dificultad / riesgo | **M** · la IA de cobertura es nueva: muestrear 8 puntos alrededor y elegir el que **rompa** la LOS del dron con `intersect_ray` contra la capa 8. Acotado, pero hay que presupuestar 8 rayos cada 0.5 s |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `facade_strafe` | ciudad | 1.0 s | el tambor gira y se enciende en rojo; barrido horizontal de una fachada, 180/s |
| `grenade_arc` | ciudad | 1.6 s | tres `Decal` de impacto previsto; granadas balísticas, 1 200 cada una |
| `gatling_burst` | dron | 1.2 s | giro audible del tambor antes de disparar; ráfaga predictiva de 2.5 s, 6/s |
| `missile_lock` | dron | **2.0 s** | retícula creciente en el `CombatHUD` + tono de lock; 4 misiles de seguimiento débil (giro máx. 45 °/s → se esquivan con un giro cerrado) |
| `shoulder_flare` | dron | 0.8 s | bengalas desde los pods; **anulan la asistencia de puntería 6 s** |

**Puntos débiles:** tambor del gatling (`WHILE_ATTACK`), visera (`ALWAYS`), **mochila de munición** (`ANGLE_CONE` 90° desde atrás; al romperse **detona** y se lleva el 25 % de su propia estructura). **Desprendibles:** brazo-gatling, pods de hombro, mochila.

**Fases (3):** P1 Supresión (a 60–90 m, cobertura) → P2 Agresivo (sin gatling: misiles + acercamiento) → P3 Último cartucho (sin pods: sólo bengalas y melee, se pega al dron).

**Boceto de `parts.json`:** `pelvis`(root) → `torso` → {`head`→`wp_visor`, `wp_backpack`(detachable), `shoulder_pod_l/r`(detachable), `arm_r_gatling`(detachable) → `wp_gatling_drum`, `arm_l`}; piernas como MechGolem.

---

### 3.5 FieldFighter — zancudo de intercepción *(WP-34)*

**Visual.** El más alto y el más delgado: dos patas larguísimas de tres segmentos, rojo oscuro y negro, sosteniendo un cuerpo pequeño y compacto arriba. A los costados, **pods cian** encendidos; al frente, dos **faros amarillos** muy intensos y un par de antenas. Silueta de insecto palo, elegante y amenazante.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Interceptor de media distancia · **hover-strider**: dos patas largas + `HoverDriver` |
| Reuso | IK de dos huesos íntegro; `GaitController` en un modo nuevo `BIPED_STRIDE` (una pata en el aire como máximo, zancadas de 18 m) |
| Personalidad | Esquivo; castiga la media distancia; huye del cuerpo a cuerpo; muy móvil |
| Dificultad / riesgo | **M** · el `HoverDriver` **desacopla la altura del cuerpo de la media de los pies**: `hip_height` pasa a ser un offset dinámico con un `Curve` de empuje. Riesgo de que "flote" sin peso si el suavizado es muy alto |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `overhead_curtain` | ciudad | 1.5 s | los pods cian cargan; cortina de disparos cenital sobre una manzana, 220/s repartidos |
| `skewer` | ciudad | 1.0 s | clava una pata en un techo; 2 600 al edificio y queda anclado 1.5 s |
| `rail_snap` | dron | **1.8 s** | línea guía brillante desde el pod; disparo **de un solo golpe** de 70 de daño. La contramedida es cortar la LOS antes del final del windup |
| `kick` | dron | 0.9 s | postura de carga sobre una pata; patada ascendente, 50 + 70 N·s hacia arriba |
| `strafe_dash` | propio | 0.6 s | reposicionamiento de 40 m en 0.8 s con el `HoverDriver`; los faros se apagan durante el vuelo |

**Puntos débiles:** rodillas finas ×2 (`ALWAYS`, muy frágiles: 700 HP), torso (`WHILE_ATTACK`). **Desprendibles:** **1 pata** — no lo mata: pasa a un modo **arrodillado**, estático y más peligroso.

**Fases (3):** P1 Cazador (móvil, `rail_snap` + `kick`) → P2 Arrodillado (1 pata perdida: torreta fija con `rail_snap` acelerado, cooldown −40 %) → P3 Sobrecarga (los pods se funden: `overhead_curtain` continuo hasta caer).

**Boceto de `parts.json`:** `core`(root) → {`wp_torso`, `pod_l/r`(weak_point), `lamp_l/r`(cosmetic, detachable), `antenna_l/r`(cosmetic, detachable)}; `leg_l/r_hip`(leg_root) → `femur`(leg_segment, detachable) → `tibia`(leg_segment) → {`foot`(foot), `wp_leg_X_knee`}.

---

### 3.6 MobileStorageBot — mula logística *(WP-35)*

**Visual.** Caja beige con **contenedores marrones** atados encima y a los lados, sobre cuatro patas finas de articulaciones **cian brillante**. Un panel frontal con un ojo rojo o azul. Pequeño, ancho y claramente civil-militarizado: no busca pelea.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Portador / **spawner** · cuadrúpedo lento |
| Reuso | **100 %** del `ProceduralLegRig` del Arachnodroid (mismos ids de pata, `hip_height` 7 m) |
| Personalidad | Evasivo; **huye del dron**; prioriza acercarse a la ciudad y descargar |
| Dificultad / riesgo | **S–M** · el único riesgo es la cadena de explosiones de contenedores, que puede matarlo en 2 s: el daño propio se limita al **35 % del HP del contenedor** |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `charge_drop` | ciudad | 1.2 s | abre un contenedor y deja una **carga con temporizador de 6 s** junto a un edificio; el jugador puede destruirla (es una parte de capa 3 con 400 HP) |
| `turret_deploy` | ciudad + dron | 1.8 s | despliega 2 torretas fijas (capa 6) que disparan a la ciudad y al dron durante 40 s |
| `evade_burst` | propio | 0.5 s | al entrar el dron en 30 m, huye a 1.6× velocidad durante 4 s |
| `container_flak` | dron | 1.0 s | ráfaga corta defensiva desde un contenedor, 4/s durante 1.5 s |
| `panic_dump` | ciudad | 1.4 s | por debajo del 40 %, suelta las 4 cargas a la vez y corre |

**Puntos débiles:** los **4 contenedores** (`ALWAYS`; al romperse **explotan**: 1 800 en radio 14 m a la ciudad y a sí mismo), articulaciones cian de las patas (`ALWAYS`). **Desprendibles:** contenedores, patas.

**Fases (2):** P1 Reparto (avanza y descarga) → P2 Pánico (< 40 %: `panic_dump` + huida a máxima velocidad).

**Boceto de `parts.json`:** `chassis`(root) → {`head_box` → `wp_sensor_eye`, `wp_container_fl/fr/bl/br`(detachable, explosivo)}; patas con los ids del Arachnodroid (`leg_fl_coxa → femur → tibia → {foot, wp_leg_fl_joint}`).

---

### 3.7 Mecha01 — duelista con escudo *(WP-36)*

**Visual.** Bípedo blanco y gris claro, angular y limpio. Sobre el brazo izquierdo, un **escudo plano enorme** que hace de visera y tapa medio cuerpo; ojos azules encendidos y una **hoja/lámpara azul** en la mano derecha. Articulaciones gris oscuro. Lee como un caballero.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Duelista · bípedo con guardia |
| Reuso | **95 % del `BipedRig`** (paso más corto, torso que reorienta el escudo hacia la amenaza) |
| Personalidad | Duelista: sigue al dron, mantiene el escudo de frente; castiga el enfrentamiento frontal |
| Dificultad / riesgo | **M** · el **bloqueo direccional** obliga a consultar la orientación del escudo antes de aplicar daño. Se resuelve con un campo nuevo `EnemyPartProfile.block_cone_deg` (0 = sin bloqueo) leído por `EnemyPart.take_damage`, sin tocar la firma del contrato con `docs/08` |

**Bloqueo direccional.** El escudo cubre un cono frontal de **120°**. Los impactos dentro del cono hacen **daño 0** y acumulan "carga de contraataque"; la contramedida es **orbitar** y pegar por el flanco o la espalda. Retroalimentación: chispazo azul y hitmarker gris en vez de blanco.

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `shield_charge` | ciudad | 1.8 s | se agacha detrás del escudo y una línea marca la trayectoria; embiste **arrasando una manzana entera** (900 por edificio atravesado) |
| `overhead_cleave` | ciudad | 1.3 s | hoja en alto; corte vertical, 2 400 al edificio |
| `charge` | dron | 1.6 s | misma postura, trayectoria marcada; 65 + 100 N·s |
| `blade_arc` | dron | 1.0 s | estela azul de la hoja; arco de 200° en 0.4 s, 55 |
| `riposte` | dron | 0.8 s | sólo si la carga de contraataque está llena: onda frontal de 30 m, 45 + aturdimiento visual 1.5 s |

**Puntos débiles:** **espalda** (`ANGLE_CONE` 100° desde atrás, `ALWAYS` dentro del cono), articulación del escudo (`WHILE_ATTACK` durante `shield_charge`). **Desprendibles:** escudo (al caer, el bloqueo desaparece), hombreras, hoja.

**Fases (3):** P1 Guardia (defensivo, espera) → P2 Agresivo (escudo dañado: más embestidas, el cono baja a 80°) → P3 Sin escudo (rápido y frágil, todo melee, ya no bloquea).

**Boceto de `parts.json`:** `pelvis`(root) → `torso` → {`head`→`wp_eyes`, `wp_back_panel`, `pauldron_l/r`(detachable), `shield_arm` → {`shield_plate`(detachable, `block_cone_deg 120`), `wp_shield_joint`}, `blade_arm` → `blade`(detachable)}; piernas estándar.

---

### 3.8 ReconBot — explorador de apoyo *(WP-37)*

**Visual.** El más pequeño: cuerpo celeste claro, **cabeza-sensor cuadrada** desproporcionada cubierta de luces indicadoras verdes, naranjas y rojas, patas finas con pies diminutos y pequeñas antenas. Parece un trípode de vigilancia que aprendió a caminar.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Explorador / soporte · bípedo ágil que **trepa** |
| Reuso | **90 % del `BipedRig`** + el trepado por rayo de apoyo del rig cuadrúpedo |
| Personalidad | **Cobarde y prioritario**: se mantiene a 60–90 m, detrás de otros enemigos y de edificios; nunca inicia combate |
| Dificultad / riesgo | **S** · el riesgo real es de **acoplamiento**: el "marcado" afecta la `Perception` de los demás enemigos. Debe viajar por `Events` (un hecho nuevo, `enemy_mark_shared`) y resolverse con `Perception.apply_shared_mark(position, seconds)`; nunca con referencias directas entre enemigos |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `target_paint` | ciudad | 1.0 s | haz fino descendente sobre un edificio; los aliados le hacen **+40 %** durante 20 s |
| `mark_drone` | dron | 1.4 s | tono agudo y anillo de aviso en el `CombatHUD`; durante **12 s** todos los enemigos reciben `believed_position` **sin ruido** (σ = 0) |
| `ally_shield` | aliado | 1.6 s | burbuja direccional sobre un aliado: −60 % de daño por el frente durante 8 s |
| `flare_blind` | dron | 0.8 s | bengala; reduce el alcance de la asistencia de puntería 6 s |
| `scramble` | propio | 0.4 s | trepa un edificio y rompe LOS |

**Puntos débiles:** **cabeza-sensor** (`ALWAYS`; concentra casi todo su HP). **Desprendibles:** cabeza — al romperla queda ciego, deja de marcar y huye hasta caer.

**Fases (2):** P1 Observador (marca y apoya) → P2 Huida (< 50 %: sólo `scramble` y `flare_blind`).

**Boceto de `parts.json`:** `pelvis`(root) → `torso` → {`wp_sensor_head`(detachable), `antenna_l/r`(cosmetic, detachable)}; `leg_l/r_thigh`(leg_root) → `shin`(leg_segment) → `foot`(foot).

---

### 3.9 Companion-bot — comandante y jefe final *(WP-38)*

**Visual.** El único **antropomorfo** del pack: androide esbelto de extremidades caqui y torso oscuro, cabeza pequeña con ojos azul y rojo, y **paneles verdes y cian** encendidos en el pecho, antebrazos y espinillas. Parece una persona con armadura: es la silueta más inquietante precisamente porque no es un monstruo.

| Dato | Valor |
|---|---|
| Arquetipo / locomoción | Comandante · **jefe final** · bípedo antropomórfico hiperágil (pasos cortos, esquivas laterales, saltos) |
| Reuso | `BipedRig` con perfil ágil; todo el framework de fases y partes |
| Personalidad | Calculador; **nunca solo**: si no le quedan escoltas vivas, prioriza `wave_command` por encima de todo |
| Dificultad / riesgo | **L** · `hud_hack` toca el HUD **y los controles del jugador**: debe ser 100 % reversible, no puede escribir en `Controls` ni en ningún `.cfg`, y necesita su propio check. Segundo riesgo: el acoplamiento con `RoundManager` para invocar oleadas |

| Ataque | Objetivo | Telegrafía | Coreografía y resolución |
|---|---|---|---|
| `wave_command` | ciudad | **2.5 s** | abre los paneles del pecho y canaliza: invoca 2–4 enemigos ya producidos vía `RoundManager`. **Es la única ventana en la que el núcleo es vulnerable** |
| `hud_hack` | dron | 2.0 s | estática creciente en el overlay FPV; al completarse, invierte un eje o apaga componentes del HUD durante **5 s**. Contramedida: cortar la LOS antes del final |
| `blink_strike` | dron | 0.9 s | dash corto + golpe; 50 + 60 N·s |
| `counter_stance` | propio | 1.2 s | durante 2 s **devuelve a la ciudad** el daño que recibe |
| `emp_lance` | dron | 1.6 s | lanza en cono de 40 m; −20 % de energía y glitch 2 s |

**Puntos débiles:** **núcleo de pecho**, expuesto sólo mientras canaliza (`WHILE_ATTACK` **∧** `AFTER_PARTS` ≥ 1 brazo, `require_all = true`). **Desprendibles:** brazos (al perderlos pierde `blink_strike` y encadena hackeos).

**Fases (4):** P1 Comandante (a distancia, invoca) → P2 Duelista (< 65 %: se acerca, `blink_strike`) → P3 Desesperado (sin brazos: hackeos encadenados y `counter_stance`) → P4 Sobrecarga (los paneles quedan abiertos permanentemente: núcleo siempre expuesto, velocidad ×1.5, 60 s para matarlo antes de que complete la última oleada).

**Boceto de `parts.json`:** `pelvis`(root) → `torso` → {`wp_chest_core`, `chest_panel_l/r`(detachable), `head`, `arm_l/r_upper`(detachable) → `forearm` → `hand`}; `shin_panel_l/r`(cosmetic emisivo); piernas estándar.

---

## 4. Orden de producción

**2 → 3 → 4 → 5 → 6 → 7 → 8 → 9**, por amortización técnica y variedad de gameplay:

| Pos. | Enemigo | Por qué va acá |
|---|---|---|
| 2 | QuadrupedTank | **Reusa 90 % del rig ya validado.** Introduce balística predictiva y anclaje sin tocar locomoción: riesgo bajo justo después del jefe, y el contraste de ritmo (asedio a distancia vs. coloso de cerca) es inmediato |
| 3 | MechGolem | El `BipedRig` va **temprano** para que lo amorticen 4, 7, 8 y 9. Si se retrasa, cuatro WPs quedan bloqueados |
| 4 | MechaTrooper | **95 % de 3**: valida el rig bípedo con otra silueta y agrega lock-on y cobertura. Barato porque llega justo después |
| 5 | FieldFighter | Rompe tres bípedos seguidos con el `HoverDriver` y una marcha de dos patas larguísimas; es el enemigo más "distinto" de jugar |
| 6 | MobileStorageBot | **100 % del rig cuadrúpedo**, casi gratis. Respiro tras tres WPs pesados y habilita un **tipo de ronda nuevo** (intercepción) sin tecnología de locomoción nueva |
| 7 | Mecha01 | El **bloqueo direccional** es la mecánica de combate más novedosa del juego; necesita el `BipedRig` estabilizado por 3 y 4 |
| 8 | ReconBot | Barato (S) y de **soporte**: sólo tiene sentido cuando ya hay varios enemigos a los que apoyar y marcar |
| 9 | Companion-bot | Jefe final: exige que existan escoltas (2–8) para su `wave_command` y el `hud_hack`, que es lo más invasivo del proyecto |

---

## 5. Tecnología nueva que introduce cada enemigo

| Enemigo | WP | Tecnología nueva | Reutilizada después por |
|---|---|---|---|
| Arachnodroid | 19 | `ProceduralLegRig`, `GaitController`, desprendimiento, fases | todos |
| QuadrupedTank | 31 | **Balística predictiva** (`RigidBody3D` capa 6 + liderado), **estado `DEPLOY`/anclaje**, **marcado por reflector** | 4, 6, 8 |
| MechGolem | 32 | **`BipedRig`** (péndulo invertido, paso alterno, recuperación de tropiezo), **agarrar y lanzar edificios** | 4, 7, 8, 9 |
| MechaTrooper | 33 | **Lock-on de misiles**, **IA de cobertura** (muestreo de puntos sin LOS), **bengalas anti-asistencia** | 7, 9 |
| FieldFighter | 34 | **`HoverDriver`** (altura desacoplada de los pies), modo de marcha `BIPED_STRIDE`, **modo arrodillado** | — |
| MobileStorageBot | 35 | **Spawner de unidades** (torretas desplegadas), **cargas con temporizador destruibles**, explosión en cadena | 9 |
| Mecha01 | 36 | **Bloqueo direccional** (`block_cone_deg`), carga de contraataque | 9 |
| ReconBot | 37 | **Marcado de objetivos** (`Events.enemy_mark_shared` + `Perception.apply_shared_mark`), **escudo aliado** | 9 |
| Companion-bot | 38 | **Hackeo de HUD y controles** (reversible), **invocación de oleadas** desde el `RoundManager` | — |

---

## 6. Rondas que habilita cada enemigo

| Ronda | Composición | Tipo | Habilitada por |
|---|---|---|---|
| 1 | Arachnodroid | Jefe | WP-19 |
| 2 | QuadrupedTank | Jefe de asedio a distancia | WP-31 |
| 3 | MechGolem | Jefe bruto de cerca | WP-32 |
| 4 | MechaTrooper + QuadrupedTank | **Mixta**: uno fija, el otro bombardea | WP-33 |
| 5 | FieldFighter ×2 | Dúo veloz de intercepción aérea | WP-34 |
| 6 | MobileStorageBot ×3 en ruta | **Intercepción**: destruirlos antes de que lleguen a descargar | WP-35 |
| 7 | Mecha01 | **Duelo**: una sola unidad, ciudad casi intacta, par time exigente | WP-36 |
| 8 | ReconBot ×2 + MechaTrooper ×2 | **Mixta con marcado**: matar primero a los exploradores | WP-37 |
| 9 | Companion-bot + escoltas | **Jefe final** con oleadas | WP-38 |

**WP-39** cierra P3: `RoundCatalog` con las 8 rondas nuevas, par times, puntajes objetivo y progresión de desbloqueo (`docs/11`).

---

## 7. Interfaz pública

P3 **no crea clases paralelas**: extiende el framework de `docs/06` con piezas acotadas y registradas.

```gdscript
class_name BipedRig extends ProceduralLegRig        # WP-32; sustituye GaitController por BipedGait
func set_stance(stance: StringName) -> void         # &"neutral" | &"guard" | &"sprint"
func trip(direction: Vector3) -> void

class_name HoverDriver extends Node                 # WP-34
@export var lift_curve: Curve
func height_offset(delta: float, base_height: float) -> float

class_name EnemyCatalog extends RefCounted          # crece con una entrada por WP
const ENTRIES := {
    &"arachnodroid": {...}, &"quadruped_tank": {...}, &"mech_golem": {...},
    &"mecha_trooper": {...}, &"field_fighter": {...}, &"storage_bot": {...},
    &"mecha01": {...}, &"recon_bot": {...}, &"companion_bot": {...},
}
```

**Campos nuevos** en recursos existentes: `EnemyPartProfile.block_cone_deg: float = 0.0` (WP-36) y `WeakPointProfile.on_destroy["explode"]: Dictionary` (WP-35).

**Señales del bus reservadas para P3**, ya declaradas en `autoloads/events.gd` desde WP-01 con estas firmas exactas (`docs/02` §5.1): `Events.enemy_mark_shared(enemy: Node3D, target_position: Vector3, seconds: float)` (WP-37, la consume `Perception.apply_shared_mark(target_position, seconds)`) y `Events.enemy_wave_requested(enemy: Node3D, wave_id: StringName)` (WP-38, la consume `RoundManager`, que resuelve `wave_id` contra la composición de la ronda). Ambas son **hechos**, nunca comandos: el emisor no sabe quién escucha.

**Capas de física** (`docs/02` §3.1): partes en **3**, puntos débiles expuestos en **4**, escombros en **9**, **balística enemiga en 6** (`projectile_enemy`, máscara 1·2·8) — estrenada por el QuadrupedTank; torretas desplegadas también en 3. Ningún `Area3D`.

**Claves de traducción:** `ENEMY_QUADRUPED_TANK`, `ENEMY_MECH_GOLEM`, `ENEMY_MECHA_TROOPER`, `ENEMY_FIELD_FIGHTER`, `ENEMY_STORAGE_BOT`, `ENEMY_MECHA01`, `ENEMY_RECON_BOT`, `ENEMY_COMPANION_BOT`, más un `ATK_*` por ataque y un `WP_*` por punto débil.

---

## 8. Parámetros y valores iniciales

Todos **propuesta**, a validar en el WP de cada enemigo.

| Enemigo | `voxel_size` | Altura | `walk_speed` | `hip_height` | `turn_rate` | HP de puntos débiles |
|---|---|---|---|---|---|---|
| Arachnodroid | 0.75 | 29.3 m | 6.0 m/s | 14.0 m | 25 °/s | 12 000 |
| QuadrupedTank | 0.42 | 23.5 m | 3.2 m/s | 9.0 m | 14 °/s | 9 000 |
| MechGolem | 0.50 | 27.0 m | 7.5 m/s (dash 50) | 12.0 m | 35 °/s | 10 500 |
| MechaTrooper | 0.36 | 21.6 m | 6.5 m/s | 10.5 m | 40 °/s | 8 000 |
| FieldFighter | 0.55 | 32.5 m | 11.0 m/s | 18.0 m (dinámico) | 55 °/s | 5 500 |
| MobileStorageBot | 0.30 | 13.8 m | 4.5 m/s (huida 7.2) | 7.0 m | 30 °/s | 6 000 |
| Mecha01 | 0.45 | 19.8 m | 8.0 m/s (embestida 26) | 9.5 m | 45 °/s | 9 500 |
| ReconBot | 0.20 | 11.8 m | 9.0 m/s | 5.5 m | 70 °/s | 3 200 |
| Companion-bot | 0.28 | 16.0 m | 10.0 m/s | 8.0 m | 80 °/s | 11 000 |

Comunes a todos: `armor_default 0.90` (0.0 en puntos débiles), `max_step_per_tick 0.6`, `debris_lifetime 20 s`, `decision_hz 4`, `top_n 3`, `personality_spread 0.30`, `perception_hz 10`, `noise_base 2.0`, `memory_seconds 4.5`, telegrafía mínima 0.9 s / 0.8 s absoluto, presupuesto de triángulos por enemigo **< 18 000** (el Arachnodroid, el más simple, va a < 12 000).

---

## 9. Criterios de aceptación y check headless

`"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/enemy_catalog_check.tscn`

Un solo check transversal del catálogo, que crece con cada WP de P3 (cada enemigo además trae su `tools/<enemy>_check.tscn` con el molde de `arachnodroid_check`, `docs/07` §13). Sale **0** al pasar, **1** con `FAIL: <enemy_id> <criterio>`, **2** si falta un recurso. Restaura `Global.round_seed` al salir.

| # | Criterio | Umbral |
|---|---|---|
| 1 | Toda entrada de `EnemyCatalog.ENTRIES` resuelve escena y perfil | `load()` no nulo; ids únicos y estables |
| 2 | Toda escena instancia y construye su grafo de partes sin errores | `Global.startup_errors` vacío tras instanciar los 9 |
| 3 | Altura real del modelo vs. la declarada en §2 | ± 0.15 m |
| 4 | Presupuesto de triángulos por enemigo | < 18 000 |
| 5 | Cada perfil declara **≥ 3 ataques**, al menos 1 contra ciudad y 1 contra dron | conteo |
| 6 | **Todo ataque con daño tiene `effective_windup() >= 0.80`** en todas sus fases | invariante del framework |
| 7 | Cada enemigo declara entre **2 y 5 fases**, monótonas y alcanzables por daño programático | sin retrocesos; se alcanza la última |
| 8 | Cada enemigo tiene ≥ 1 punto débil y ≥ 1 parte `detachable` | conteo |
| 9 | Claves de traducción presentes en `translations.csv` | `ENEMY_*`, `ATK_*`, `WP_*` sin faltantes |
| 10 | Capas: 0 `Area3D` usados como hitbox en las 9 escenas | conteo 0 |
| 11 | Ningún enemigo referencia rutas fuera de `res://` ni de otro repositorio | grep del check |
| 12 | Coste: instanciar los 9 y simular 5 s cada uno | física < 2.0 ms/tick por enemigo |

---

## 10. Riesgos y decisiones abiertas

| # | Riesgo / decisión | Mitigación o pendiente |
|---|---|---|
| 1 | **QuadrupedTank, 28 400 voxels**: la segmentación por cajas puede no cerrar | `exclude` + componentes conexos como asistente; `_unassigned` en magenta; `--report` falla si queda alguno. Es el caso que justifica el fallback Blender de `docs/05` |
| 2 | **`Mecha01.rar`**: `unzip` no lo abre | **Cerrado (2026-09-19)**: se extrae **fuera del repo** con `"C:\Program Files\WinRAR\UnRAR.exe"`, que está instalado en la máquina de desarrollo. Mecha01 **no** sale del alcance y el orden de producción de §4 se mantiene |
| 3 | **`BipedRig`**: cuatro WPs dependen de él | WP-32 es **L** y no se cierra sin su propio `biped_gait_check` (mismas métricas que `gait_check` más "nunca dos pies en el aire" y "recuperación de tropiezo < 1.5 s") |
| 4 | **`hud_hack`** modifica HUD y controles del jugador | reversible por construcción, sin tocar `Controls` ni los `.cfg`; check dedicado que verifica la restauración exacta tras 5 s y tras un respawn |
| 5 | Marcado compartido (ReconBot) acopla enemigos entre sí | va por `Events` como hecho; `Perception` lo consume, nadie guarda referencias cruzadas |
| 6 | Explosiones en cadena del MobileStorageBot lo matan solo | daño propio limitado al 35 % del HP del contenedor; verificado en su check |
| 7 | Nueve enemigos × ~10 000 HP de puntos débiles = peleas muy largas si se combinan | las rondas mixtas usan HP reducido (×0.6) respecto de la ficha individual; se fija en WP-39 |
| 8 | **Abierto:** escalas de §2 | son propuestas geométricas; se confirman con la ciudad montada (una torre de FreeSample mide 12–16 m, así que el ReconBot de 11.8 m es "del tamaño de un edificio bajo") |
| 9 | **Abierto:** ¿el FieldFighter arrodillado debe poder morir? | propuesta: sí, pero con el torso expuesto permanentemente; evaluar si resulta anticlimático |
| 10 | **Abierto:** balística real vs. hitscan para QuadrupedTank y MechaTrooper | la capa 6 está reservada para proyectiles físicos; si el coste es alto, caer a hitscan con retardo simulado |
| 11 | **Abierto:** licencias de los packs voxel | `docs/16` — a verificar antes de publicar; no bloquea la producción |

---

## 11. Referencias cruzadas

- `docs/05-pipeline-voxel.md` — `parts.json`, meshing, GLB e import; todos los bocetos de §3 son entradas para ese pipeline.
- `docs/06-framework-de-enemigos.md` — clases, recursos, telegrafía, fases y el contrato de §13 que cada enemigo nuevo debe cumplir.
- `docs/07-arachnodroid.md` — molde de ficha y de check para los 8 restantes.
- `docs/08-combate-y-armas.md` — daño, multiplicadores y asistencia de puntería que las bengalas y el bloqueo direccional modifican.
- `docs/10-ciudad-destructible.md` — `Building.take_damage(amount, point)`, que usan todos los ataques contra la ciudad.
- `docs/11-rondas-y-objetivos.md` — `RoundCatalog`, composición de las rondas de §6 y la invocación de oleadas del jefe final.
- `docs/12-interfaz-y-hud.md` — marcadores de objetivo, aviso de lock-on y el HUD que `hud_hack` interviene.
- `docs/13-identidad-visual-y-audio.md` — emisivos, haces, glitch y bancos de audio por enemigo.
- `docs/15-verificacion-y-ci.md` — `enemy_catalog_check` y los checks por enemigo.
- `docs/16-licencias-y-atribucion.md` — licencias de los packs voxel a verificar antes de publicar.
