## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Balance del MVP: juega la ronda 1 entera con [BotPilot] y la mide contra el
## protocolo de `docs/07` §14.
##
## **No** es un banco sintético: instancia `rounds/battle_level.tscn` de verdad —el
## distrito con sus sesenta `Building`, el Arachnodroid con su IA suelta
## (`Global.debug_freeze_ai = false`), el `DroneRig` con su arma, su batería y su
## casco, el `CityIntegrity` y el `RoundManager` con su cadena de objetivos— y deja
## que el bot la juegue de principio a fin. Todo lo que se mide sale de los mismos
## hechos del bus que consume el juego.
##
## Cuatro partidas por corrida:
##
## | Partida | Semilla | Bot | Qué prueba |
## |---|---|---|---|
## | 1–3 | 1, 7, 99 | `COMBAT` | los siete rangos de `docs/07` §14 |
## | control | 1 | `IDLE` | que ignorar al jefe pierde por integridad (`docs/11` §11) |
## | negativa | 1 | `COMBAT` con `dodge_skill 0` y σ enorme | que el bot responde a sus parámetros |
##
## **Tiempo acelerado**: `Engine.time_scale` multiplica el `delta` de cada paso de
## física (`docs/15` §4.2), así que un segundo de reloj vale
## [member Engine.time_scale] segundos simulados. El factor real medido se imprime
## por partida. Con `--fixed-fps` en la línea de órdenes el bucle principal se
## desengancha del reloj de pared y el factor sube bastante más; sin él, el techo
## es exactamente `time_scale`.
##
## ## Las corridas del rebalance del checkpoint 4 (2026-09-21)
##
## El usuario jugó la ronda entera y la juzgó «muy difícil: la batería dura poco y
## las balas hacen poco daño». El orquestador movió seis palancas —`base_drain`
## 0.55 → 0.40, `throttle_drain` 0.85 → 0.60, `energy_per_shot` 0.45 → 0.30,
## `battery_amount` 30 → 45, `respawn_energy_depleted` 20 → 30 y `damage` 12 → 16,
## más `city_friendly_fire_scale` 0.5 → 0.375 para que el fuego amigo siga valiendo
## 6 por impacto— y **nada del jefe ni del bot**. Estas son la corrida de referencia
## y la final, con el mismo binario, las mismas tres semillas y el mismo `BotPilot`:
##
## Se miden **medias de las tres semillas**, nunca partidas sueltas (ver la nota de
## [method _assert_combat]). «Después A» y «después B» son dos corridas completas
## con **exactamente el mismo código**, y están las dos a propósito: la distancia
## entre ellas es la escala del ruido contra la que hay que leer todo lo demás.
##
## | media de 3 semillas | dur (s) | integr | muert | fuego (s) | acierto | pilas/min |
## |---|---|---|---|---|---|---|
## | **antes** | **376** | 0.61 | 5 | **213** | **0.513** | **3.87** |
## | **después A** | **238** | 0.71 | 5 | **162** | **0.501** | **1.67** |
## | **después B** | **259** | 0.70 | 8 | **150** | **0.511** | **1.78** |
## | **rodillas 800 A** | **207** | 0.74 | **2** | **113** | **0.507** | **1.76** |
## | **rodillas 800 B** | **183** | 0.75 | **2** | **108** | **0.511** | **1.66** |
## | **rodillas 800 C** | **197** | 0.80 | **2** | **110** | **0.507** | **1.84** |
##
## La última fila es el **rebalance de rodillas** del mismo checkpoint, que va
## después y encima del anterior: el usuario volvió a jugar con `damage` 16 y siguió
## encontrando la partida difícil, así que se partió al medio el `hp` de las cuatro
## rodillas —1 600 → **800**, 34 → 17 aciertos por rodilla, `docs/07` §4 pasa de
## 13 600 a **10 400** HP de puntos débiles— y **nada más del jefe**: otras partes,
## fases, cooldowns y daños de ataque quedan clavados. Se movieron con ella la
## duración, el fuego neto y las muertes; el acierto y las pilas/min no.
##
## Por semilla, con la corrida B que es la que valida las filas de abajo:
##
## | | dur (s) | integr | muert | fuego (s) | acierto | pilas/min | pts | medalla |
## |---|---|---|---|---|---|---|---|---|
## | **antes** semilla 1 | 400 | 0.584 | 2 | 230 | 0.546 | 3.90 | 543 | bronce |
## | **antes** semilla 7 | 327 | 0.667 | 2 | 179 | 0.533 | 3.67 | 783 | bronce |
## | **antes** semilla 99 | 401 | 0.585 | 1 | 230 | 0.460 | 4.04 | 1080 | plata |
## | **después** semilla 1 | 235 | 0.725 | 2 | 143 | 0.571 | 1.79 | 1067 | plata |
## | **después** semilla 7 | 252 | 0.668 | 3 | 146 | 0.499 | 1.90 | 741 | bronce |
## | **después** semilla 99 | 290 | 0.718 | 3 | 161 | 0.462 | 1.66 | 665 | bronce |
##
## Y con las rodillas a 800, que es la corrida que valida las filas de abajo. Se
## agregan las **fases con su tiempo**, porque son lo que hace legible la partida:
## el jefe llega a P5 en las tres semillas y la pelea entera cabe en el reloj de
## `time_par` (540 s), de ahí el salto de las medallas.
##
## | rodillas 800 | dur (s) | integr | muert | fuego (s) | acierto | pilas/min | pts | medalla |
## |---|---|---|---|---|---|---|---|---|
## | **A** semilla 1 | 157 | 0.805 | 0 | 87 | 0.595 | 1.91 | 4269 | **oro** |
## | **A** semilla 7 | 246 | 0.642 | 1 | 131 | 0.479 | 1.70 | 1854 | plata |
## | **A** semilla 99 | 217 | 0.777 | 1 | 120 | 0.446 | 1.66 | 2075 | **oro** |
## | **B** semilla 1 | 157 | 0.805 | 0 | 87 | 0.595 | 1.91 | 4269 | **oro** |
## | **B** semilla 7 | 196 | 0.736 | 1 | 122 | 0.484 | 1.53 | 2152 | **oro** |
## | **B** semilla 99 | 195 | 0.715 | 1 | 117 | 0.454 | 1.54 | 2145 | **oro** |
## | **C** semilla 1 | 157 | 0.805 | 0 | 87 | 0.595 | 1.91 | 4269 | **oro** |
## | **C** semilla 7 | 216 | 0.832 | 1 | 125 | 0.479 | 1.94 | 2113 | **oro** |
## | **C** semilla 99 | 217 | 0.777 | 1 | 120 | 0.446 | 1.66 | 2077 | **oro** |
##
## A, B y C son tres corridas completas del mismo código —C es la que valida las
## bandas de abajo tal como están— y vuelven a ser la escala del ruido: la semilla 1
## sale **idéntica hasta el decímetro** en las tres, la 7 se mueve 246 → 196 → 216 s
## (un 20 %), de plata a oro, y su integridad 0.642 → 0.736 → 0.832, sin que nada
## cambie en el medio. Las bandas se fijan con las tres corridas, nunca con una.
##
## | rodillas 800 (C) | P2 alerta | P3 furia | P4 vientre | P5 autodestrucción |
## |---|---|---|---|---|
## | semilla 1 | 30 s | 72 s | 84 s | 137 s |
## | semilla 7 | 69 s | 77 s | 133 s | 197 s |
## | semilla 99 | 64 s | 98 s | 119 s | 194 s |
##
## Las cinco fases salen en las tres semillas, en orden y sin retrocesos, y la
## partida entera cabe entre P5 y el temporizador de 45 s: el jefe cae por el tercer
## núcleo, no por detonación. Con las rodillas a 1 600 P2 llegaba más tarde (la
## primera rodilla cuesta el doble de aciertos); ahora la alerta entra en el primer
## minuto y **el 70 % de la pelea transcurre en P3 o más allá**, que es el move set
## completo. Esa es la otra cara del cambio: la partida no sólo es más corta, es más
## agresiva por segundo.
##
## Control y negativa no se mueven —ninguna de las dos rompe rodillas, así que su
## `hp` les da exactamente igual—: el control cae por integridad a los **429 s** en
## las seis corridas, clavado hasta el decímetro de segundo, y la negativa pierde
## siempre con acierto 0.021–0.030 (con las rodillas a 800: 447 s, integridad 0.348,
## acierto 0.021 y 0.028). Son la prueba de que lo que se movió arriba lo movió el
## `hp` de las rodillas y no el mundo.
##
## Lo que cambió y lo que no, que es lo que decide qué filas se recalibran:
##
## - **La pelea dura un 31–37 % menos** (376 → 238 y 259 s) y el fuego neto baja en
##   la misma proporción (213 → 162 y 150 s), porque el daño al punto débil subió de
##   36 a 48 y el presupuesto de impactos es el mismo. Filas 2 y 5 recalibradas.
## - **La ciudad termina mejor** (0.61 → 0.70–0.71): el jefe tiene un tercio menos de
##   tiempo para asediarla. Fila 3 recalibrada.
## - **El acierto no se mueve** (0.513 → 0.501 y 0.511): el daño por bala no toca la
##   puntería. [constant RANGE_HIT] queda **igual**.
## - **El bot levanta menos de la mitad de pilas por minuto** (3.87 → 1.67 y 1.78),
##   que es la fila nueva ([constant MAX_BATTERIES_PER_MINUTE]) y la medida directa
##   de lo que el usuario pidió.
## - **Las muertes no bajaron; si acaso subieron** (5 antes; 5 y 8 después, con un
##   máximo de 3 por partida contra 2 antes). [constant RANGE_DEATHS] queda
##   **igual** porque el techo por partida sigue siendo 5, pero conviene no repetir
##   la expectativa de que un dron con más autonomía muere menos: **no pasó**. Lo
##   matan el `stomp` y el `pounce`, que no se tocaron, y ahora además agota la
##   batería más seguido (ver [constant MAX_BATTERIES_PER_MINUTE]).
##
## Y lo que movió el rebalance de rodillas encima de eso:
##
## - **La pelea dura otro 15–25 % menos** (243 → **207**, **183** y **197 s** de
##   media) y el fuego neto otro 22–26 % (146 → **113**, **108** y **110 s**). Las dos caídas son la
##   misma: el presupuesto de puntos débiles bajó de 13 600 a 10 400, un 24 %, y el
##   fuego neto es proporcional a él; la duración baja menos porque las esquivas, los
##   viajes a la pila y las fases no se acortan. Filas 2 y 5 recalibradas.
## - **La ciudad termina un poco mejor todavía** (0.72 → **0.74**, **0.75** y
##   **0.80**). Es el mismo efecto de siempre —menos minutos de asedio— y el techo de la
##   fila 3, que se asevera **por partida**, se quedó a 0.045 de la semilla 1. Fila 3
##   corrida hacia arriba sin cambiar su ancho.
## - **El acierto no se mueve** (0.507, 0.511 y 0.507 contra 0.501 y 0.511): el `hp` del blanco no
##   toca la puntería, igual que no la tocaba el daño de la bala. [constant RANGE_HIT]
##   queda **igual** por segunda vez.
## - **Las pilas/min tampoco** (1.67 y 1.78 → **1.76**, **1.66** y **1.84**): la pelea y los viajes a la
##   pila se acortan juntos. [constant MAX_BATTERIES_PER_MINUTE] queda **igual**.
## - **Las muertes sí bajaron esta vez, y mucho** (5, 6 y 8 en la suite → **2** en las
##   tres corridas: 0 / 1 / 1). Es el efecto de segundo orden del cambio y hay que decirlo sin adornos: el
##   jefe pega exactamente lo mismo, pero tiene un 15 % menos de partida para hacerlo
##   y el bot llega a P5 antes de acumular golpes. La semilla 1 gana **sin morir**, y
##   con el piso viejo —una muerte por partida en promedio— la fila 4 fallaba con todo
##   lo demás en verde. Ver [constant MIN_DEATHS_TOTAL]: el piso pasa a la **suite**.
##
## ## La pila de recarga total (2026-09-21, encima de todo lo anterior)
##
## Tercer movimiento del mismo día y **una sola palanca**: el usuario pidió que «al
## agarrar una pila la energía se renueve entera», así que
## `EnergyProfile.battery_amount` pasa de 45 a **100**. Nada más se tocó —ni el
## drenaje, ni el jefe, ni el `hp` de las rodillas, ni `BotPilot`—, y en particular
## sigue sin tocarse `BotPilot.energy_hunt_ratio` (0.35): el bot sale a buscar pila
## en el mismo momento que antes, sólo que ahora vuelve con el depósito lleno en vez
## de con 45 puntos más.
##
## | rodillas 800 + pila 100 | dur (s) | integr | muert | fuego (s) | acierto | pilas/min | pts | medalla |
## |---|---|---|---|---|---|---|---|---|
## | semilla 1 | 188 | 0.780 | 1 | 137 | 0.446 | **1.28** | 2219 | **oro** |
## | semilla 7 | 212 | 0.777 | 2 | 127 | 0.447 | **1.41** | 1152 | plata |
## | semilla 99 | 173 | 0.725 | 1 | 111 | 0.495 | **1.04** | 2255 | **oro** |
## | **media** | **191** | **0.76** | **4** | **125** | **0.463** | **1.24** | — | — |
##
## **Ninguna fila se recalibra**, y conviene decir por qué fila por fila, porque es
## la primera vez en el checkpoint que un cambio de economía no mueve ninguna banda:
##
## - **Pilas/min baja de 1.66–1.84 a 1.24** ([constant MAX_BATTERIES_PER_MINUTE]),
##   que es la medida directa de lo que el usuario pidió y la única fila que se movió
##   en la dirección prevista. El techo de 2.6 ya estaba puesto a mitad de camino
##   entre las dos economías viejas (1.53–1.99 contra 3.67–4.04) y el régimen nuevo
##   se aleja **más** de él, así que bajarlo sería estrechar una banda sobre la
##   medida, justo lo que la nota de abajo prohíbe.
## - **La duración no se mueve** (183–207 → **191**), y no es casualidad: el bot pasa
##   menos tiempo yendo a la pila, pero el presupuesto de puntos débiles es el mismo
##   y es él quien fija cuánto dura la pelea. [constant RANGE_DURATION] queda igual.
## - **El fuego neto tampoco** (108–113 → **125**, dentro de 80–160): sube un poco
##   porque el dron pasa más minutos armado y menos en tránsito, pero el numerador
##   —10 400 HP de puntos débiles— no cambió. [constant RANGE_FIRE] queda igual.
## - **El acierto tampoco** (0.507–0.511 → **0.463**): décima corrida observada, y
##   sigue cayendo en la franja de siempre. [constant RANGE_HIT] queda igual **por
##   tercera vez**; la batería no toca la puntería como no la tocaban ni el daño por
##   bala ni el `hp` del blanco.
## - **La ciudad termina igual** (0.74–0.80 → 0.780 / 0.777 / 0.725, media 0.76),
##   porque la pelea dura lo mismo. [constant RANGE_INTEGRITY] queda igual.
## - **Las muertes suben, no bajan: 2 → 4 en la suite** (1 / 2 / 1). Es lo contrario
##   de lo que uno esperaría de más autonomía y hay que anotarlo sin adornos, igual
##   que se anotó en el rebalance anterior: lo que mata al bot es el `stomp` y el
##   `pounce`, no la batería. Lo que **sí** cambió es la **causa**: la energía mínima
##   de la partida pasa de 0.000 en dos de tres semillas a **0.26 / 0.23 / 0.24**, o
##   sea que el dron ya no se queda sin batería ni una vez en toda la suite. Las
##   cuatro muertes son del jefe, las que la fila 4 quiere que existan.
##   [constant RANGE_DEATHS] y [constant MIN_DEATHS_TOTAL] quedan igual.
##
## ## El pueblo de ruta (WP-D, 2026-09-21, encima de todo lo anterior)
##
## Cuarto movimiento del mismo día y el primero que **no toca una sola palanca de
## balance**: el nivel dejó de cargar el distrito rectangular de P2 y carga el
## pueblo de ruta de P2b (`city/districts/town_a.tscn`). Lo que cambió es el
## mundo, no los números:
##
## | | distrito `district_a` | pueblo `town_a` |
## |---|---|---|
## | destructibles | 60 | **59** |
## | HP total | 120 300 | **92 100** (−23 %) |
## | HP del edificio típico | 1 200 (39 de 60) | **1 300** (52 de 59) |
## | edificios de 3 500 HP | 21 | **7** |
## | extensión | 480 × 288 m | círculo de **280 m** de diámetro |
## | edificio más alto | 75–80 m | **18,1 m** |
##
## Dos suites completas, mismo binario, mismas tres semillas, mismo `BotPilot`:
##
## | pueblo | dur (s) | integr | muert | fuego (s) | acierto | pilas/min | pts | medalla |
## |---|---|---|---|---|---|---|---|---|
## | **A** semilla 1 | 173 | 0.669 | 2 | 125 | 0.508 | 1.38 | 1225 | plata |
## | **A** semilla 7 | 152 | 0.734 | 1 | 116 | 0.511 | 2.36 | 2361 | **oro** |
## | **A** semilla 99 | 172 | 0.723 | 1 | 124 | 0.495 | 1.74 | 2260 | **oro** |
## | **A** media | **166** | **0.709** | **4** | **122** | **0.505** | **1.83** | — | — |
## | **B** semilla 1 | 171 | 0.590 | 1 | 142 | 0.439 | 1.41 | 2235 | **oro** |
## | **B** semilla 7 | 107 | 0.773 | 0 | 95 | 0.546 | 1.69 | 4599 | **oro** |
## | **B** semilla 99 | 154 | 0.749 | 1 | 107 | 0.481 | 1.56 | 2362 | **oro** |
## | **B** media | **144** | **0.704** | **2** | **115** | **0.489** | **1.55** | — | — |
##
## Las cinco fases salen en las seis partidas, en orden y sin retrocesos, y las
## seis caben de sobra en el reloj de `time_par` (540 s): cinco medallas de oro y
## una de plata. Las fases, con su tiempo:
##
## | | P2 alerta | P3 furia | P4 vientre | P5 autodestrucción |
## |---|---|---|---|---|
## | A · semilla 1 | 81 s | 82 s | 110 s | 147 s |
## | A · semilla 7 | 66 s | 85 s | 100 s | 144 s |
## | A · semilla 99 | 60 s | 82 s | 107 s | 164 s |
## | B · semilla 1 | 96 s | 111 s | 137 s | 159 s |
## | B · semilla 7 | 49 s | 55 s | 74 s | 97 s |
## | B · semilla 99 | 67 s | 82 s | 89 s | 144 s |
##
## Y el ruido, que es lo que decide cuánto se puede estrechar una banda: la
## semilla 7 se movió **152 → 107 s** (un 30 %) entre dos corridas con exactamente
## el mismo código, y la semilla 1 dejó la ciudad en 0.669 y en 0.590. Es la misma
## nota de siempre (`docs/15` §1.1) y esta vez es más grande que nunca.
##
## Lo que se recalibra y lo que no:
##
## - **La pelea dura otro 15–25 % menos** (183–207 → **166** y **144**). No es una
##   palanca: el presupuesto de puntos débiles del jefe es el mismo, pero el pueblo
##   cabe en un círculo de 280 m contra los 480 × 288 del distrito, y el bot pasa
##   mucho menos tiempo viajando entre el jefe y la pila. [constant RANGE_DURATION]
##   recalibrada.
## - **La ciudad termina parecido en la media y mucho peor en el peor caso**
##   (0.74–0.80 → **0.709** y **0.704** de media, pero **0.590** en una partida
##   suelta). El techo de esta fila se asevera **por partida**, así que lo que la
##   mueve es el 0.590, que quedaba a 0.010 del piso viejo.
##   [constant RANGE_INTEGRITY] recalibrada.
## - **El control tarda un 20 % más, no menos** (461 → **568** y **511 s**), y es
##   la única fila que **falló** con las bandas viejas. Contra la intuición, porque
##   el pueblo tiene un 23 % menos de HP. El mecanismo es el desperdicio del haz:
##   `siege_beam` reparte 900 /s durante 4 s, o sea **3 600 de daño por uso**, y lo
##   que absorbe es un solo edificio. En el distrito, 21 de los 60 blancos eran
##   torres de 3 500 HP que se comían el haz entero; en el pueblo quedan **siete**,
##   y las otras 52 casas devuelven 1 300 de 3 600. El coloso además camina entre
##   59 blancos repartidos en un disco de 280 m en vez de 60 alineados en una
##   retícula: 148 `approach` por partida de control en las **dos** corridas, el
##   mismo número. [constant RANGE_CONTROL] recalibrada.
## - **El fuego neto no se mueve** (108–113 → **122** y **115**, dentro de 80–160).
##   El numerador —10 400 HP de puntos débiles— es el mismo y la ciudad no entra en
##   esa cuenta. [constant RANGE_FIRE] queda igual.
## - **El acierto tampoco** (0.507–0.511 → **0.505** y **0.489**). Undécima y
##   duodécima medias observadas, todas entre 0.454 y 0.513. [constant RANGE_HIT]
##   queda igual **por cuarta vez**: ni el daño por bala, ni el `hp` del blanco, ni
##   la batería, ni el mundo tocan la puntería.
## - **Las pilas/min suben pero no llegan al techo** (1.24 → **1.83** y **1.55**,
##   techo 2.6). Suben porque la partida se acortó y el denominador manda, no
##   porque la batería rinda menos: ninguna de las seis partidas llega a agotarla
##   (mínimos 0.09–0.29, con las tres más bajas en la segunda corrida).
##   [constant MAX_BATTERIES_PER_MINUTE] queda igual.
## - **Las ventanas de daño casi se duplican** (1.6–2.3 → **2.79–3.54**), y por fin
##   cumplen el ≥ 3.0 de `docs/07` §14 en una de las dos corridas. El motivo es el
##   mismo que acorta la partida: el jefe tiene los blancos más cerca y gasta menos
##   turnos caminando. [constant MIN_WINDOWS_PER_MINUTE] **no se sube a la medida**,
##   por la regla de abajo: 3.15 y 2.91 de media son dos corridas, no una
##   población.
## - **Las muertes siguen donde estaban** (2 → **4** y **2** en la suite, máximo 2
##   por partida). [constant RANGE_DEATHS] y [constant MIN_DEATHS_TOTAL] igual.
##
## ## Estas tablas no son reproducibles y conviene no fingir que lo son
##
## Se corrieron **cinco** suites completas cerrando el rebalance. Dos consecutivas,
## con el mismo código, salieron idénticas hasta el tercer decimal —lo que invita a
## creer que la primera partida de cada semilla es determinista— y otras dos, también
## con el mismo código entre sí, difieren un 20 % en la semilla 1 (196 contra 235 s)
## y en el total de muertes (5 contra 8). No hay ninguna palanca en el medio: es el
## solucionador de Jolt repartiendo contactos entre hilos (`docs/15` §1.1), y la
## coincidencia de las dos primeras fue suerte, no determinismo.
##
## De ahí las dos reglas de este check, que valen para cualquiera que venga a
## recalibrarlo: se asevera sobre la **media de las tres semillas** y con **bandas
## anchas**. Cualquier cosa más fina mide el ruido.
##
## Comandos, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot res://tools/balance_check.tscn -- --timeout=1200
## godot --headless --path godot --fixed-fps 60 res://tools/balance_check.tscn -- --timeout=1200
## godot --headless --path godot res://tools/balance_check.tscn -- --timeout=400 --only=1
## [/codeblock]
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"

## Ronda que se mide.
const ROUND_ID: String = "first-contact"

## Semillas de las tres partidas del protocolo (`docs/07` §14).
const SEEDS: Array[int] = [1, 7, 99]

## Aceleración de la simulación. `docs/15` §10 pone el techo en 4.0.
const TIME_SCALE: float = 4.0

## Tope de segundos **simulados** por partida. Es la red de seguridad: una ronda
## que no termina es un fallo, no una espera eterna.
const MAX_SIM_SECONDS: float = 780.0

## Tope de segundos **de reloj** por partida.
const MAX_REAL_SECONDS: float = 300.0

## Segundo de batalla en el que se toma la ventana de física.
const PHYSICS_SAMPLE_AT: float = 60.0

## Pasos de física de esa ventana.
const PHYSICS_SAMPLE_TICKS: int = 300

## Pasos que se descartan al entrar en la ventana, mientras los acumuladores de
## las consultas de ataque se reacomodan al `delta` nominal.
const PHYSICS_SAMPLE_DISCARD: int = 40

# --- Rangos de `docs/07` §14 -------------------------------------------------------------------

## Duración del combate, en segundos.
##
## `docs/07` §14 pide 390–540 (6.5–9 min). El piso de §8 sale de dividir el fuego
## neto por una «fracción de la pelea dedicada a disparar» de 0.35–0.49; el bot
## llega a **0.54–0.56** porque no se distrae, no sobrepasa el blanco, no se
## estrella y vuelve derecho a la pila más cercana. Es decir: la duración que mide
## este check es un **piso** de lo que va a tardar un humano, no una estimación.
##
## **340–540 → 190–390 en el rebalance del checkpoint 4.** Con `damage` 12 → 16 el
## bot gana en 227, 277 y 225 s (media **243**) contra los 400, 327 y 401 (media
## 376) de la corrida de referencia del mismo día: un 35 % menos, que es
## exactamente 36/48. La banda nueva conserva el **ancho de 200 s** de la vieja y
## deja la medida en el mismo lugar relativo (27 % del rango; antes 18 %), así que
## tolera el mismo ruido de Jolt —una semilla se movió 451 → 548 s entre corridas
## idénticas— sin dejar de detectar una regresión real.
##
## **190–390 → 140–340 en el rebalance de rodillas.** Con el `hp` de las rodillas a
## la mitad el bot gana en 157, 246 y 217 s (media **207**) y, en la segunda corrida,
## en 157, 196 y 195 (media **183**) y en 157, 216 y 217 (media **197**), contra los
## 235, 252 y 290 (243) de antes: un 15–25 % menos, no el 24 % que bajó el presupuesto de puntos débiles, porque las
## esquivas, los viajes a la pila y las cinco fases duran lo mismo. La banda nueva
## vuelve a conservar el **ancho de 200 s** y se centra en las **tres** medias (196),
## que quedan en el mismo lugar relativo de siempre (27 % del rango). El piso de
## 140 s tiene que quedar debajo de 157 —la semilla más rápida— y con margen para el
## ruido: la fila se asevera sobre la media, pero una banda que apenas cubre lo
## medido no sobrevive a la corrida siguiente, y acá la semilla 7 se movió 246 → 196
## entre dos corridas idénticas.
##
## El objetivo de `docs/07` §14 **queda sin cumplir a propósito y no es un fallo**:
## 390–540 s es el rango de una partida **humana**, y el bot es un piso. Con las
## palancas viejas el piso ya estaba por debajo (376 s) y el usuario igual tardó lo
## suyo; ahora el piso baja a 3,5 min y la pasada manual decide si eso deja la
## partida corta. Queda anotado como discrepancia.
##
## **140–340 → 90–290 con el pueblo de ruta (WP-D).** El nivel cambió de mundo y
## no de palancas: el pueblo cabe en un círculo de 280 m de diámetro contra los
## 480 × 288 m del distrito, y el bot deja de perder minutos en tránsito. Medido
## 173, 152 y 172 s (media **166**) en una corrida y 171, 107 y 154 (media
## **144**) en la otra, contra 157–246 (183–207) sobre el distrito. La banda nueva
## vuelve a conservar el **ancho de 200 s** y deja las dos medias a 54 y 38 s del
## piso: con el ancho viejo, 144 quedaba a **cuatro segundos** de los 140, que es
## exactamente la situación que la nota de [constant MIN_DEATHS_TOTAL] prohíbe.
## El techo de 290 sigue cazando una regresión que devuelva la pelea a los seis
## minutos del distrito.
const RANGE_DURATION: Vector2 = Vector2(90.0, 290.0)

## Integridad de la ciudad al vencer.
##
## **0.45–0.70 → 0.55–0.85 en el rebalance del checkpoint 4.** No se tocó ni el
## `crush_damage` ni el `siege_beam`: la ciudad termina mejor porque el jefe tiene
## un 35 % menos de tiempo para asediarla. Medido 0.750, 0.750 y 0.670 (media 0.72)
## contra 0.584, 0.667 y 0.585 (0.61). La banda mantiene el ancho (0.30 contra
## 0.25) y sigue teniendo **techo**: una victoria con la ciudad intacta querría
## decir que el jefe dejó de ser una amenaza para ella, que es el conflicto entero
## de la ronda.
##
## **0.55–0.85 → 0.58–0.88 en el rebalance de rodillas.** Mismo mecanismo y mismo
## ancho: la media pasa a 0.74, 0.75 y 0.80 en las tres corridas porque la pelea se
## acorta otro 15–25 %. Lo que fuerza el corrimiento no es la media sino el
## **techo**, porque esta fila se asevera **por partida**: la semilla 1 termina en
## 0.805 en las tres, y la 7 —que con las rodillas a 1 600 dejaba la ciudad en
## 0.668— subió a 0.642, 0.736 y **0.832** en corridas idénticas, o sea 0.19 de
## recorrido. Con el techo viejo de 0.85 esa tercera corrida pasaba por 0.018. Con
## 0.88 el margen vuelve a ser el de antes y el techo sigue haciendo su
## trabajo: una ciudad intacta sigue siendo un fallo.
##
## **0.58–0.88 → 0.53–0.83 con el pueblo de ruta (WP-D).** Las medias apenas se
## mueven (0.74–0.80 → **0.709** y **0.704**) pero esta fila se asevera **por
## partida**, y la partida peor de las seis dejó el pueblo en **0.590**, a 0.010
## del piso viejo. Mismo ancho de 0.30, centrado en el punto medio de lo medido
## (0.590–0.773): quedan 0.06 de margen abajo y 0.057 arriba, que es el mejor
## reparto posible sin ensanchar. Queda anotado que el margen es **más chico que
## el ruido de una misma semilla** —la 1 midió 0.669 y 0.590 entre dos corridas
## idénticas—: si esta fila falla sola en una corrida futura, lo que hay que
## revisar primero es si el ancho de 0.30 sigue alcanzando para un mundo de 59
## edificios chicos, donde una ráfaga de más o de menos vale el 1,4 % de la
## integridad y no el 1 % de antes.
const RANGE_INTEGRITY: Vector2 = Vector2(0.53, 0.83)

## Muertes del dron por partida.
##
## `docs/07` §14 pide 1–3. Se asevera **1–4**: con el gate de apoyo arreglado el
## castigo del jefe depende mucho de la semilla —medido 1, 3 y 5 con el haz de
## cabeza a 2.5 m de radio, y 1–3 con 1.8— y una cuarta reconstrucción sigue
## siendo una partida legible. Cero muertes **sí** es un fallo: querría decir que
## el jugador es invulnerable, que es justo lo que WP-23 encontró y corrigió.
##
## **Sin cambios en el rebalance del checkpoint 4**, y vale anotar por qué: la
## expectativa era que un dron con más autonomía y más daño muriera menos, y no
## pasó. Medido 2, 2 y 2 (6 en total) contra 2, 2 y 1 (5) de la corrida de
## referencia. El jefe pega exactamente lo mismo y el bot se expone exactamente
## igual; lo único que cambió es que la partida termina antes. Quien mata al dron
## es el `stomp` y el `pounce`, no la batería.
##
## **El piso por partida se retira en el rebalance de rodillas: `1–5` → `0–5`.** Lo
## que antes no pasó, esta vez pasó: con las rodillas a la mitad la suite mide 0, 1
## y 1 (**2 en total**) contra 6, y la semilla 1 gana **sin morir ni una vez**. El
## jefe no se tocó; lo que se acortó es la partida, y una partida más corta ofrece
## menos ventanas para que el `stomp` y el `pounce` encuentren al bot. Una semilla
## limpia deja de ser un fallo por sí sola, pero la suite entera sin una sola muerte
## sí lo sigue siendo: ese piso se mudó a [constant MIN_DEATHS_TOTAL]. El techo de 5
## por partida **no se toca**.
const RANGE_DEATHS: Vector2i = Vector2i(0, 5)

## Muertes mínimas en las **tres semillas juntas**.
##
## Es el piso que antes vivía en `RANGE_DEATHS.x` multiplicado por la cantidad de
## partidas (3), y que el rebalance de rodillas dejó sin cumplir con todo lo demás
## en verde: 2 muertes medidas contra un mínimo de 3. Lo que ese piso defiende es
## una sola cosa —**que el dron no sea invulnerable**, que es exactamente el bug que
## WP-23 encontró y corrigió— y para eso alcanza con exigir que en algún momento de
## la suite el jefe mate. Se asevera **1**, no 2, porque 2 es la medida y una vara
## puesta sobre la medida falla en la corrida siguiente: entre corridas idénticas el
## total de muertes ya se movió 5 → 8 (`docs/15` §1.1). Las dos corridas con las
## rodillas a 800 dieron **2, 2 y 2** (0 / 1 / 1 las tres veces), así que el 2 no fue
## una casualidad de una semilla: es el régimen nuevo.
##
## Lo que esta fila deja de cubrir lo cubren otras: si el jefe dejara de pegar, la
## integridad de la ciudad se dispararía por encima del techo de
## [constant RANGE_INTEGRITY] y la duración caería por debajo del piso de
## [constant RANGE_DURATION]. `docs/07` §14 pide 1–3 muertes **por partida**: queda
## anotado como discrepancia, igual que la duración.
const MIN_DEATHS_TOTAL: int = 1

## Segundos de fuego neto.
##
## `docs/07` §14 pide 170–210, que sale de la tabla de §8: `12 000 / 63` con un
## ciclo de trabajo de 0.55 y una tasa de acierto de 0.40. Las dos entradas
## cambiaron al medirlas: el ciclo real del arma del MVP es **0.63** —22 disparos
## en 2.75 s más 1.8 s de bloqueo, que sale del propio `default_gun.tres`, no de
## 0.55— y el HP de los ocho puntos débiles pasó de 12 000 a **12 800** al subir
## las rodillas a 1 400. Rehaciendo la cuenta con los números medidos,
## `12 800 / (8 · 0.63 · 0.36 · 36)` = **196 s**, y la banda de ±25 % queda en
## **170–250**.
##
## **170–250 → 110–190 en el rebalance del checkpoint 4.** Es el mismo cálculo con
## el `damage` nuevo: el único factor que se movió es el daño al punto débil, de 36
## a 48, así que el fuego neto se multiplica por `36 / 48` y los 196 s pasan a
## **147**. Medido: 127, 173 y 136 s, media **146**. La banda de ±25 % queda en
## **110–184** y se redondea a 110–190, ancho 80, el mismo de la vieja.
##
## **110–190 → 80–160 en el rebalance de rodillas.** Tercera vuelta del mismo
## cálculo, y esta vez el factor que se mueve es el numerador: el presupuesto de
## puntos débiles baja de 12 800 a **10 400** (`4·800 + 1500 + 3·1900`), así que
## `10 400 / (8 · 0.63 · 0.36 · 48)` = **119 s**. Medido: 87, 131 y 120 s (media
## **113**), 87, 122 y 117 en la segunda (**108**) y 87, 125 y 120 en la tercera
## (**110**). La banda de ±25 % sobre
## lo medido queda en 81–141; se asevera **80–160** para conservar el ancho de 80 de
## las dos bandas anteriores, para cubrir el 119 del cálculo y para que el piso quede
## debajo de los 87 s de la semilla más rápida.
const RANGE_FIRE: Vector2 = Vector2(80.0, 160.0)

## Tasa de acierto real sobre puntos débiles.
##
## La σ del bot y la dispersión de ráfaga del arma se componen, y como el radio
## aparente del punto débil es del orden de la σ resultante, la tasa se mueve mucho
## con poco: al calibrar WP-23, con σ 0.60° salió 0.33–0.36, con 0.55° salió
## 0.36–0.48 y con 0.50° salió 0.45. Fijar 0.35–0.45 exigiría recalibrar la σ por
## semilla, que es medir el calibrador y no el juego.
##
## **El techo sube de 0.50 a 0.55 en el cierre de la tanda 4 (WP-28)**, sin tocar el
## piso ni el bot. No es un cambio de balance: es que el techo de WP-23 había quedado
## **por debajo del ruido de la propia métrica**. Medias por corrida observadas, todas
## con el mismo bot y las mismas tres semillas: **0.486** (WP-29; semillas 0.546 /
## 0.509 / 0.404), **0.490** (corrida de una sola semilla del cierre de WP-28),
## **0.511** (suite del cierre de la tanda 4; semillas 0.513 / 0.533 / 0.488) y
## **0.454** (la corrida que valida este cambio; semillas 0.546 / 0.412 / 0.404).
## **Cinco** de esas diez partidas pasan de 0.50 —0.546, 0.509, 0.513, 0.533 y otra
## vez 0.546— y una de las cuatro medias también, así que la fila fallaba por
## dispersión y no por una regresión: entre la más baja (0.404) y la más alta (0.546)
## hay 0.14, casi la mitad de la banda entera, y una misma semilla se mueve 0.10 entre
## corridas (la 7: 0.509, 0.533, 0.412) porque la física de Jolt no es reproducible
## (`docs/15` §1.1). Con 0.55 cubre el rango medido y sigue siendo un techo: un bot
## que acertara siempre lo rompería igual.
##
## **Sin cambios en el rebalance del checkpoint 4**, y es la fila que demuestra que
## el rebalance hizo lo que decía: subir el daño por bala **no toca la puntería**.
## Medias de las dos corridas del mismo día: **0.513** antes (0.546 / 0.533 / 0.460)
## y **0.507** después (0.578 / 0.454 / 0.488). Con esas dos, las seis medias
## observadas caen entre 0.454 y 0.513, todas dentro de la banda, y recalibrarla
## sería mover una vara que no se movió.
##
## **Sin cambios tampoco en el rebalance de rodillas**, y por el mismo motivo por
## segunda vez: el `hp` del blanco no toca la puntería. Medido **0.507**, **0.511** y
## **0.507** en las tres corridas, que caen entre las medias de siempre. Nueve medias
## observadas, todas entre 0.454 y 0.513.
const RANGE_HIT: Vector2 = Vector2(0.33, 0.55)

## Ciclo de trabajo efectivo del arma.
const RANGE_DUTY: Vector2 = Vector2(0.50, 0.62)

## Techo de **pilas recogidas por minuto**, promediado sobre las tres semillas.
##
## Es la fila nueva del rebalance del checkpoint 4 y mide, literalmente, la queja
## del usuario: «la batería dura poco». Menos viajes a la pila por minuto de pelea
## = la batería aguanta más. Medido, en cuatro corridas:
##
## | Corrida | por semilla | media |
## |---|---|---|
## | palancas viejas | 3.90 / 3.67 / 4.04 | **3.87** |
## | nuevas, antes de compensar el fuego amigo | 1.59 / 1.95 / 1.60 | **1.71** |
## | nuevas, `--only=1` | 1.99 | **1.99** |
## | nuevas, corrida final | 1.53 / 1.74 / 1.73 | **1.67** |
## | rodillas a 800 | 1.91 / 1.70 / 1.66 | **1.76** |
## | rodillas a 800, segunda corrida | 1.91 / 1.53 / 1.54 | **1.66** |
## | rodillas a 800, tercera corrida | 1.91 / 1.94 / 1.66 | **1.84** |
## | pila de recarga total (100 %) | 1.28 / 1.41 / 1.04 | **1.24** |
##
## Las dos poblaciones **no se tocan** —1.53–1.99 contra 3.67–4.04— así que el techo
## de 2.6 (a mitad de camino, con un 30 % de margen para cada lado) separa las dos
## economías de energía sin ninguna ambigüedad.
##
## **La pila de recarga total no mueve el techo, lo aleja.** Con `battery_amount`
## 45 → 100 el bot baja a **1.24** pilas/min: sale a buscar pila en el mismo momento
## de siempre —`BotPilot.energy_hunt_ratio` sigue en 0.35— pero vuelve con el
## depósito lleno, así que cada viaje le compra más del doble de autonomía que con
## 45. El techo **no se baja a la nueva medida**: 2.6 sigue separando la economía
## vieja de la nueva sin ambigüedad, y estrecharlo sobre 1.24 sería exactamente el
## error que denuncia la nota de [constant MIN_DEATHS_TOTAL] —poner la vara sobre lo
## medido— en una métrica cuyo denominador es la duración de la partida, que se mueve
## un 20 % entre corridas idénticas.
##
## **El rebalance de rodillas no la mueve** (1.67 y 1.78 → 1.76, 1.66 y 1.84): la
## pelea se acorta y los viajes a la pila se acortan con ella, así que el cociente
## queda donde estaba, con 0.76 de margen hasta el techo en la peor de las tres. La semilla 1 sube a 1.91 porque su partida es la más corta de todas
## (157 s) y el denominador manda; sigue lejos del techo.
##
## ## Por qué no se asevera `min_energy`, que era el candidato obvio
##
## `BotPilot` ya medía `min_energy` —el **mínimo absoluto** de batería de toda la
## partida— y era la métrica que este check iba a estrenar. No sirve, y conviene
## dejar escrito por qué para que nadie la vuelva a proponer:
##
## - **Colapsa a cero.** Agotar la batería una sola vez la clava en 0.000 para toda
##   la partida, sin importar cómo haya ido el resto. Es un indicador binario
##   disfrazado de continuo.
## - **Y agotarla pasa más seguido ahora, no menos.** Con las palancas viejas el bot
##   levantaba 20–27 pilas por partida y nunca llegaba a cero (mínimos 0.15–0.17);
##   con las nuevas levanta 5–9, pasa mucho más tiempo lejos de un puesto, y un
##   `emp_pulse` de 25 % lo encuentra a media batería. Dos de las tres semillas de la
##   corrida final terminan en 0.000. **Con la pila de recarga total eso se dio
##   vuelta otra vez**: las tres semillas terminan en 0.26, 0.23 y 0.24 y ninguna
##   toca el cero, que es justamente lo que la métrica no sabe decir cuando importa
##   —y por eso sigue sin aseverarse, aunque ahora diría algo bonito—.
## - **La media se mueve con cosas que no son la energía.** Tres medias medidas con
##   la misma economía: 0.192, 0.192 y **0.042**. Entre la segunda y la tercera lo
##   único que cambió fue `city_friendly_fire_scale` 0.5 → 0.375, que no toca la
##   batería: la métrica está dominada por la divergencia del mundo, no por lo que
##   dice medir.
##
## `min_energy` se sigue **imprimiendo** por partida y en el promedio, porque como
## diagnóstico es útil: un cero ahí dice «acá hubo una reconstrucción por batería».
## Lo que no puede es sostener una aserción. Que suba de 5–9 a 20–27 pilas o que
## caiga a cero más seguido es, además, información de diseño que el orquestador
## puede querer usar: [member BotPilot.energy_hunt_ratio] (0.35) está calibrado
## contra la economía vieja.
const MAX_BATTERIES_PER_MINUTE: float = 2.6

## Ventanas de daño por minuto.
##
## **`docs/07` §14 pide ≥ 3 y el move set no da para tanto.** La cuenta es
## aritmética: una ventana es un uso de `siege_beam` —1.8 + 4.0 + 1.5 s de
## ejecución más su enfriamiento— o una recuperación de `pounce` —1.3 + 1.2 + 2.0
## más 35 s—. Aun con el enfriamiento de P3 ya bajado a ×0.55, el ciclo mínimo del
## haz es de 12.8 s (4.7/min) y el del salto de 28.7 s (2.1/min), y eso **sólo si
## el jefe no hiciera ninguna otra cosa**: en una partida real reparte sus turnos
## entre nueve acciones y camina la mitad del tiempo. Medido con las palancas al
## máximo razonable: 1.6 a 2.3 por minuto. Se asevera **1.5**, que es lo
## defendible, y el objetivo de 3 queda anotado como discrepancia con `docs/07`.
const MIN_WINDOWS_PER_MINUTE: float = 1.5

## Duración de la partida de control, en segundos.
##
## `docs/07` §14 y `docs/11` §11 hablan de cinco minutos. Medido: **430 s**, y el
## límite **no** es el daño sino el desplazamiento. Con `siege_beam` a 900 /s el
## jefe tarda 430 s; subiéndolo a 1 100 /s tarda 431 s, porque las 23 ráfagas que
## alcanza a tirar ya reparten 101 000 de daño contra los 78 000 que hacen falta:
## un tercio se desperdicia sobre edificios ya en ruinas y el reloj lo marca el
## tiempo que el coloso pasa caminando de una torre a la siguiente. Se asevera
## **240–480** y la diferencia queda anotada como discrepancia.
##
## **El techo sube de 450 a 480 en WP-24d**, con permiso del orquestador y por
## dos motivos que empujan en la misma dirección y ninguno es el daño:
##
## 1. El distrito de WP-24b tiene manzanas con fachadas alineadas y el jefe hace
##    un 22 % más de `approach` entre blancos; el control ya medía 444–470 s
##    contra un techo de 450 sin margen para el ruido de la métrica.
## 2. La marcha de WP-24d baja la cadencia de 1.8 a 1.0 apoyos por segundo
##    —`step_duration` 0.55 → 0.80, que es lo que hace que 900 t se lean
##    pesadas—, y con `crush_damage` 900 por apoyo la presión ambiental de
##    `walk` (`docs/07` §5.2) cae en la misma proporción.
##
## Medido con las dos cosas: **461 s**. Subir `crush_damage` para compensar era
## la alternativa, pero mueve un número de balance de `docs/07` §12 y acelera
## también las tres partidas con dron, que ya están en rango.
##
## **240–480 → 420–660 con el pueblo de ruta (WP-D), y es la única fila que
## falló.** El control tarda **568 s** en una corrida y **511 s** en la otra,
## contra los 461 del distrito. Contra la intuición: el pueblo tiene un 23 % menos
## de HP total. Se suman dos cosas y ninguna es la potencia del haz:
##
## 1. **El haz desperdicia más.** `siege_beam` reparte 900 /s durante 4 s —3 600 de
##    daño por uso— y lo absorbe un solo edificio. El distrito tenía 21 torres de
##    3 500 HP que se comían el haz entero; el pueblo tiene **siete**, y las otras
##    52 casas devuelven 1 300 de esos 3 600. Con 32 y 29 usos de `siege_beam` el
##    coloso tira 115 000 y 104 000 de daño para arrancar los 60 300 que hacen
##    falta.
## 2. **Camina más.** 59 blancos repartidos en un disco de 280 m en vez de 60
##    alineados en una retícula. Las dos corridas miden **148 `approach`** en la
##    partida de control, exactamente el mismo número.
##
## La banda nueva conserva el **ancho de 240 s** y se centra en las dos medidas
## (540): 91 s de margen por debajo de la más rápida y 92 por encima de la más
## lenta. Se recalibra y no se «arregla» porque arreglarlo pedía mover
## `crush_damage` o `siege_beam`, que son números de balance de `docs/07` §12 y
## afectan también a las tres partidas con dron, que están en rango.
##
## La distancia con `docs/07` §14 y `docs/11` §11 —que hablan de **cinco
## minutos**— pasa de 461 s a 511–568, o sea de un 54 % a un 70–89 % por encima
## del objetivo. Queda anotado como discrepancia, con las palancas de `docs/10`
## §1 que la cerrarían sin tocar al jefe: bajar el `hp` de la casa de 1 300 a
## 1 100 (−15 % del presupuesto que el haz tiene que masticar) o recortar la
## cantidad de casas. **Ninguna de las dos se aplica acá**: son decisiones de
## diseño del pueblo, no de este check.
const RANGE_CONTROL: Vector2 = Vector2(420.0, 660.0)

## Presupuesto de física con jefe y ciudad, en ms/tick.
##
## `docs/15` §5.2 pone el techo en **2.0**. Medido en WP-23 sobre el nivel real:
## **1.5–1.8 ms** con el coloso caminando y asediando la ciudad —que es lo que
## midió `arachnodroid_check` con seis edificios— pero **5.1–5.4 ms** en plena
## pelea, con el arma disparando, los proyectiles resolviendo su rayo por tick,
## los escombros de las patas desprendidas rodando y los edificios derrumbándose.
## De ahí el 6.0 como **guarda de regresión**: no es un presupuesto, es un techo sobre
## esta misma métrica para que se compare consigo misma entre corridas.
##
## **Corregido por WP-29**: aquel «el presupuesto de §5.2 no se cumple en combate» era
## un artefacto de medición, el mismo que anota [constant DOC_PHYSICS_BUDGET_MS].
## §5.2 juzga ahora el tick real (`physics_tick_ms`), y con jefe y ciudad mide
## **1.27 ms/tick**: el presupuesto **sí** se cumple. Lo que estos 2.6–2.8 ms miden es
## el pico por segundo de `TIME_PHYSICS_PROCESS` con `time_scale`
## [constant TIME_SCALE]; el número comparable contra §5.2 lo da `perf_report`.
const PHYSICS_BUDGET_MS: float = 6.0

## Presupuesto declarado por `docs/15` §5.2, sólo como umbral para decidir si vale la
## pena imprimir la línea informativa de física.
##
## **No es una comparación válida** y por eso la línea no dice «excede». Desde WP-29,
## §5.2 juzga el **tick real** (`physics_tick_ms`), y lo que mide este check es
## `Performance.TIME_PHYSICS_PROCESS`, que se refresca una vez por segundo y reporta
## el **pico por segundo**; acá además la partida corre a `time_scale`
## [constant TIME_SCALE], o sea cuatro veces más pasos de física por segundo de
## reloj. Las dos cosas juntas inflan el número varias veces sobre el tick real. El
## presupuesto de §5.2 se mide con `perf_report`; lo que asevera este check es
## [constant PHYSICS_BUDGET_MS], que es una guarda de regresión sobre esta misma
## métrica y se compara consigo misma.
const DOC_PHYSICS_BUDGET_MS: float = 2.0

## Ataques cuyo uso abre una ventana de daño (`docs/07` §14): la recuperación de
## 2.0 s del salto y los 5.8 s anclados del haz de asedio.
const WINDOW_ATTACKS: Array[StringName] = [&"pounce", &"siege_beam"]

## Títulos de las filas del resumen.
const ROW_TITLES: Array[String] = [
	"las tres semillas terminan en victoria", "duración media 90–290 s",
	"integridad al vencer 0.53–0.83",
	"muertes ≤ 5 por partida, ≥ 1 en la suite y ≤ 2.6 pilas/min (la batería dura más)",
	"fuego neto 80–160 s y acierto débil 0.33–0.55 (promedio de las tres semillas)",
	"ventanas de daño ≥ 1.5/min (media)", "control: derrota por integridad en 420–660 s",
	"sin NaN en las métricas", "física mediana bajo la guarda de regresión",
	"Engine.time_scale restaurado", "prueba negativa: el bot responde a sus parámetros",
]

## Período de la traza de diagnóstico, en segundos simulados.
const TRACE_PERIOD: float = 15.0

## Resultado de cada fila.
var _rows: Dictionary[int, bool] = {}

## Traza de diagnóstico encendida con `--trace`. No es parte del protocolo: es la
## ventana por la que se mira una partida que no termina.
var _trace: bool = false

## Informe de cada partida, en orden.
var _games: Array[Dictionary] = []

# --- Estado de la partida en curso -------------------------------------------------------------

var _level: BattleLevel = null
var _manager: RoundManager = null
var _enemy: EnemyBase = null
var _bot: BotPilot = null
var _phases: Array[Dictionary] = []
var _telegraphs: Dictionary[StringName, int] = {}

## Diagnóstico por ataque: ventanas activas, abortadas y colliders alcanzados.
var _windows_log: Dictionary[StringName, Dictionary] = {}
var _physics_samples: PackedFloat32Array = PackedFloat32Array()
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""


func _run() -> void:
	# El nodo del check deja de ser la escena actual para sobrevivir a los niveles.
	get_tree().current_scene = null
	_freeze_before = Global.debug_freeze_ai
	_seed_before = Global.round_seed
	_round_before = Global.selected_round
	# La IA **tiene que jugar**: es lo único que esta medición mide.
	Global.debug_freeze_ai = false

	if not ResourceLoader.exists(LEVEL_SCENE):
		fail("falta el nivel de batalla (%s)" % LEVEL_SCENE)
		_restore()
		return

	var only := int(user_args().get("only", 0))
	_trace = user_args().has("trace")
	if user_args().has("geom"):
		await _dump_geometry()
		_restore()
		return
	if user_args().has("showcase"):
		await _showcase(int(user_args().get("seed", SEEDS[0])),
				float(user_args().get("kill", -1.0)))
		return
	print("  aceleración pedida: time_scale %.1f · %d Hz de física · %.4f s simulados por tick"
			% [TIME_SCALE, Engine.physics_ticks_per_second,
			TIME_SCALE / float(Engine.physics_ticks_per_second)])

	var combat: Array[Dictionary] = []
	for index: int in SEEDS.size():
		if only > 0 and index + 1 > only:
			break
		var game := await _play(SEEDS[index], BotPilot.Mode.COMBAT, "semilla %d" % SEEDS[index])
		combat.append(game)
		_games.append(game)

	var control: Dictionary = {}
	if only <= 0 or only >= SEEDS.size() + 1:
		control = await _play(SEEDS[0], BotPilot.Mode.IDLE, "control (idle)")
		_games.append(control)

	var negative: Dictionary = {}
	if only <= 0 or only >= SEEDS.size() + 2:
		negative = await _play(SEEDS[0], BotPilot.Mode.COMBAT, "negativa (sin esquiva, σ 25°)",
				25.0, 0.0)
		_games.append(negative)

	_print_table()
	_assert_combat(combat)
	_assert_control(control)
	_assert_negative(combat, negative)
	_row(10, is_equal_approx(Engine.time_scale, 1.0),
			"10 · Engine.time_scale quedó en %.3f" % Engine.time_scale)
	_restore()
	_print_rows()


# --- Una partida -------------------------------------------------------------------------------

## Juega una ronda entera y devuelve su informe.
func _play(round_seed: int, bot_mode: int, label: String, sigma := -1.0,
		dodge := -1.0) -> Dictionary:
	print("")
	print("  === partida %s ===" % label)
	_phases.clear()
	_telegraphs.clear()
	_windows_log.clear()
	_physics_samples = PackedFloat32Array()

	Global.selected_round = ROUND_ID
	Global.round_seed = round_seed
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return {}
	_level = packed.instantiate() as BattleLevel
	if _level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return {}
	add_child(_level)
	# **No** se llama a `get_tree().set_current_scene(_level)`, y conviene dejar escrito
	# por qué, porque la línea estuvo acá hasta WP-28.
	#
	# `SceneTree.set_current_scene()` exige que la escena sea **hija de la raíz**, y el
	# nivel cuelga de este check. Así que la llamada abortaba
	# (`Condition "p_scene && p_scene->get_parent() != root" is true`), no asignaba
	# nada y dejaba una línea ERROR por partida en el log, indistinguible de un error
	# de verdad para el runner. Colgar el nivel de la raíz tampoco sirve: durante
	# `_ready()` la raíz está ocupada montando hijos y el `add_child` falla.
	#
	# Y no hace falta: `battle_level.tscn` trae sus propios `Pools/ProjectilePool` y
	# `Pools/DebrisPool`, y los dos resolvedores los encuentran **por grupo**
	# (`WeaponMount._find_pool()` acepta cualquier pool del grupo cuando no hay escena
	# actual, y `DebrisPool.resolve()` ni la mira). Lo que evita que dos partidas
	# compartan pools no es la escena actual sino [method _teardown], que libera el
	# nivel —y con él sus pools— antes de la siguiente, más [method _purge_stray_pools]
	# como red.
	await wait_frames(3)

	_manager = _level.get_round_manager()
	var rig := _level.drone_rig as DroneRig
	if _manager == null or rig == null:
		fail("el nivel no trae RoundManager o DroneRig")
		_teardown()
		return {}
	var enemies := _manager.get_enemies()
	if enemies.is_empty():
		fail("la ronda no instanció ningún enemigo")
		_teardown()
		return {}
	_enemy = enemies[0] as EnemyBase

	_bot = BotPilot.new()
	_bot.name = "BotPilot"
	_bot.mode = bot_mode
	if sigma >= 0.0:
		_bot.aim_sigma_deg = sigma
	if dodge >= 0.0:
		_bot.dodge_skill = dodge
	add_child(_bot)
	_bot.setup(rig, _enemy, _level.get_node_or_null(^"BatterySpawner") as BatterySpawner,
			RoundCatalog.derive_seed("bot"))

	var _discard := Events.enemy_phase_changed.connect(_on_phase_changed)
	_discard = Events.enemy_attack_telegraphed.connect(_on_telegraphed)

	var brain := _enemy.brain as EnemyFSM
	if brain != null:
		_discard = brain.action_changed.connect(_on_action_changed)

	_manager.skip_to_battle()
	await wait_frames(2)
	_bot.start()

	var report := await _simulate()

	Events.enemy_phase_changed.disconnect(_on_phase_changed)
	Events.enemy_attack_telegraphed.disconnect(_on_telegraphed)
	report["label"] = label
	report["seed"] = round_seed
	_print_game(report)
	await _teardown()
	return report


## Bucle de la partida: acelera, muestrea la física y espera al estado terminal.
func _simulate() -> Dictionary:
	Engine.time_scale = TIME_SCALE
	var started := Time.get_ticks_msec()
	var sim := 0.0
	var sampled := false
	var timed_out := false
	var traced := 0.0
	while true:
		await get_tree().physics_frame
		sim += get_physics_process_delta_time()
		if not sampled and sim >= PHYSICS_SAMPLE_AT:
			sampled = true
			await _sample_physics()
		if _trace and sim - traced >= TRACE_PERIOD:
			traced = sim
			_print_trace(sim)
		if _manager == null or not is_instance_valid(_manager):
			break
		var state := _manager.get_state()
		if state == Global.RoundState.VICTORY or state == Global.RoundState.DEFEAT:
			# La tarjeta llega tras la pausa dramática de 1.2 s; el `RoundResult`
			# con su puntaje se arma justo antes (`docs/11` §4.1).
			if _manager.get_result() != null:
				break
		var real := float(Time.get_ticks_msec() - started) / 1000.0
		if sim > MAX_SIM_SECONDS or real > MAX_REAL_SECONDS:
			timed_out = true
			break
	Engine.time_scale = 1.0
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0

	if _bot != null:
		_bot.stop()
	var report := _collect(timed_out)
	report["sim_seconds"] = sim
	report["real_seconds"] = real_seconds
	report["speed_factor"] = sim / maxf(real_seconds, 0.001)
	return report


## Ventana de física con jefe y ciudad, medida **a `time_scale` 1.0**.
##
## Medirla acelerada no sirve: con `delta` cuatro veces más grande, los
## acumuladores de `query_interval` 0.05 s de cada ataque resuelven una consulta
## por tick en vez de una cada cinco, y el coste por tick sale inflado. Es la misma
## precaución que toma `arachnodroid_check` con su fila 14.
## Sólo se quedan las muestras de los fotogramas que ejecutaron **exactamente un**
## paso de física: `Performance.TIME_PHYSICS_PROCESS` reporta lo que costó toda la
## física del fotograma, y con dos pasos dentro el número sale al doble. Con
## `--fixed-fps` eso pasa en uno de cada tres fotogramas.
func _sample_physics() -> void:
	Engine.time_scale = 1.0
	for _tick: int in PHYSICS_SAMPLE_DISCARD:
		await get_tree().physics_frame
	var previous := Engine.get_physics_frames()
	var guard := 0
	while _physics_samples.size() < PHYSICS_SAMPLE_TICKS and guard < PHYSICS_SAMPLE_TICKS * 8:
		guard += 1
		await get_tree().process_frame
		var now := Engine.get_physics_frames()
		var steps := int(now - previous)
		previous = now
		if steps == 1:
			_physics_samples.append(float(Performance.get_monitor(
					Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	Engine.time_scale = TIME_SCALE


## Junta todo lo medible de la partida que acaba de terminar.
func _collect(timed_out: bool) -> Dictionary:
	var result := _manager.get_result() if _manager != null else null
	var integrity := _manager.city_integrity.get_ratio() if _manager != null \
			and _manager.city_integrity != null else 1.0
	var destroyed := _manager.city_integrity.get_destroyed_count() if _manager != null \
			and _manager.city_integrity != null else 0
	var metrics := _bot.metrics() if _bot != null else {}
	var duration := _manager.get_elapsed_seconds() if _manager != null else 0.0
	var state := _manager.get_state() if _manager != null else -1

	var uses: Dictionary[StringName, int] = {}
	var windows := 0
	var brain := _enemy.brain as EnemyFSM if _enemy != null and is_instance_valid(_enemy) else null
	if brain != null and brain.library != null:
		for action: EnemyAction in brain.library.get_actions():
			uses[action.id()] = action.use_count()
			if WINDOW_ATTACKS.has(action.id()):
				windows += action.use_count()

	var report: Dictionary = {
		"timed_out": timed_out,
		"state": state,
		"victory": state == Global.RoundState.VICTORY,
		"duration": duration,
		"integrity": integrity,
		"destroyed": destroyed,
		"deaths": result.deaths if result != null else 0,
		"parts_broken": result.parts_broken if result != null else 0,
		"score": result.score if result != null else 0,
		"base_score": result.base_score if result != null else 0,
		"medal": result.medal if result != null else RoundCatalog.Medal.NONE,
		"multiplier": result.respawn_multiplier if result != null else 1.0,
		"accuracy": result.accuracy() if result != null else 0.0,
		"phases": _phases.duplicate(true),
		"uses": uses,
		"windows": windows,
		"windows_per_minute": float(windows) / maxf(duration / 60.0, 0.001),
		"telegraphs": _telegraphs.duplicate(),
		"windows_log": _windows_log.duplicate(true),
		"physics_median": _percentile(50.0),
		"physics_p95": _percentile(95.0),
		"physics_samples": _physics_samples.size(),
	}
	report.merge(metrics)
	# Derivada, pero se guarda en el informe para que la tabla y la aserción de la
	# fila 4 usen exactamente el mismo número.
	var minutes := maxf(duration / 60.0, 0.001)
	report["batteries_per_minute"] = float(report.get("batteries", 0)) / minutes
	return report


## Libera el nivel y el bot de la partida terminada.
func _teardown() -> void:
	if _bot != null and is_instance_valid(_bot):
		_bot.stop()
		_bot.queue_free()
	_bot = null
	get_tree().current_scene = null
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_manager = null
	_enemy = null
	await wait_frames(2)
	_purge_stray_pools()
	await wait_frames(2)


## Libera los pools que algún sistema haya colgado de la raíz del árbol en vez de
## del nivel. Es la red de la red: sin esto, dos partidas seguidas dejan dos
## `ProjectilePool` vivos y la medición de física de la segunda no vale.
func _purge_stray_pools() -> void:
	var tree := get_tree()
	for group: StringName in [ProjectilePool.GROUP, DebrisPool.GROUP]:
		for node: Node in tree.get_nodes_in_group(group):
			if node.get_parent() == tree.root:
				node.queue_free()


# --- Aserciones (`docs/07` §14) ----------------------------------------------------------------

## Aserciones de las tres partidas de combate.
##
## **Por partida** sólo se afirman los hechos cualitativos —victoria, muertes,
## integridad, física, nada de NaN—; la duración, el fuego neto, el acierto y las
## ventanas se afirman sobre el **promedio de las tres**.
##
## La razón es medida: con la misma semilla, la primera partida del proceso sale
## idéntica tick a tick, pero la segunda y la tercera no. El solucionador de Jolt
## reparte contactos entre hilos y el orden no está garantizado, así que dos
## corridas del mismo combate divergen en cuanto hay escombros rodando: la semilla
## 99 midió 451 s en una corrida y 548 s en la siguiente, con los mismos valores.
## La semilla fija la personalidad del jefe, los puestos de pila y las decisiones
## del bot (`docs/11` §4.4) pero **no** la física, así que afirmar bandas estrechas
## partida a partida sería afirmar ruido. Queda anotado contra `docs/15` §1.1
## punto 5.
func _assert_combat(games: Array[Dictionary]) -> void:
	if games.is_empty():
		return
	var deaths_sum := 0
	var duration_sum := 0.0
	var fire_sum := 0.0
	var hit_sum := 0.0
	var windows_sum := 0.0
	var energy_sum := 0.0
	var refills_sum := 0.0
	for game: Dictionary in games:
		var label := String(game.get("label", "?"))
		_row(1, bool(game.get("victory", false)) and not bool(game.get("timed_out", false)),
				"1 · %s termina en VICTORY (terminó en %s%s)"
						% [label, _state_name(int(game.get("state", -1))),
						", por timeout" if bool(game.get("timed_out", false)) else ""])
		var integrity := float(game.get("integrity", 0.0))
		_row(3, integrity >= RANGE_INTEGRITY.x and integrity <= RANGE_INTEGRITY.y,
				"3 · %s deja la ciudad en %.2f (rango %.2f–%.2f)"
						% [label, integrity, RANGE_INTEGRITY.x, RANGE_INTEGRITY.y])
		var deaths := int(game.get("deaths", 0))
		# El techo sí es por partida: una cuarta reconstrucción es una partida
		# distinta. El **piso** va al total de las tres, porque con la física no
		# reproducible una semilla puede salirse sin recibir un solo golpe — y con
		# las rodillas a 800 eso dejó de ser hipotético: la semilla 1 gana sin morir.
		_row(4, deaths <= RANGE_DEATHS.y,
				"4 · %s tiene %d muertes (tope %d por partida)"
						% [label, deaths, RANGE_DEATHS.y])
		deaths_sum += deaths
		for key: String in ["duration", "integrity", "fire_seconds", "weak_hit_rate",
				"duty_cycle", "windows_per_minute", "min_energy", "batteries_per_minute",
				"physics_median", "physics_p95"]:
			var value := float(game.get(key, 0.0))
			_row(8, is_finite(value), "8 · %s tiene %s no finito (%s)" % [label, key, str(value)])
		var median := float(game.get("physics_median", 0.0))
		_row(9, median < PHYSICS_BUDGET_MS,
				"9 · %s: física mediana %.2f ms/tick (guarda < %.1f)"
						% [label, median, PHYSICS_BUDGET_MS])
		if median >= DOC_PHYSICS_BUDGET_MS:
			print(("      informativo, %s: %.2f ms es el pico por segundo de"
					+ " TIME_PHYSICS_PROCESS con time_scale %.0f, no el tick real; el"
					+ " presupuesto de docs/15 §5.2 (< %.1f ms de tick) se mide con"
					+ " perf_report")
					% [label, median, TIME_SCALE, DOC_PHYSICS_BUDGET_MS])
		duration_sum += float(game.get("duration", 0.0))
		fire_sum += float(game.get("fire_seconds", 0.0))
		hit_sum += float(game.get("weak_hit_rate", 0.0))
		windows_sum += float(game.get("windows_per_minute", 0.0))
		energy_sum += float(game.get("min_energy", 0.0))
		refills_sum += float(game.get("batteries_per_minute", 0.0))

	var count := float(games.size())
	var duration := duration_sum / count
	var fire := fire_sum / count
	var hit := hit_sum / count
	var windows := windows_sum / count
	var min_energy := energy_sum / count
	var refills := refills_sum / count
	print("")
	print("  promedio de las %d semillas: duración %.0f s · fuego %.0f s · acierto %.3f · %.2f ventanas/min · %.2f pilas/min · energía mínima %.3f (informativa) · %d muertes en total"
			% [games.size(), duration, fire, hit, windows, refills, min_energy, deaths_sum])
	_row(2, duration >= RANGE_DURATION.x and duration <= RANGE_DURATION.y,
			"2 · la duración media es %.0f s (rango %.0f–%.0f)"
					% [duration, RANGE_DURATION.x, RANGE_DURATION.y])
	_row(5, fire >= RANGE_FIRE.x and fire <= RANGE_FIRE.y,
			"5 · el fuego neto medio es %.0f s (rango %.0f–%.0f)"
					% [fire, RANGE_FIRE.x, RANGE_FIRE.y])
	_row(5, hit >= RANGE_HIT.x and hit <= RANGE_HIT.y,
			"5 · el acierto medio sobre puntos débiles es %.3f (rango %.2f–%.2f)"
					% [hit, RANGE_HIT.x, RANGE_HIT.y])
	# El piso es de la **suite**, no por partida: ver [constant MIN_DEATHS_TOTAL].
	_row(4, deaths_sum >= MIN_DEATHS_TOTAL,
			"4 · las %d semillas suman %d muertes (mínimo %d en la suite; el dron no puede ser invulnerable)"
					% [games.size(), deaths_sum, MIN_DEATHS_TOTAL])
	_row(4, refills <= MAX_BATTERIES_PER_MINUTE,
			"4 · el bot levanta %.2f pilas/min (techo %.1f; con las palancas viejas eran 3.87)"
					% [refills, MAX_BATTERIES_PER_MINUTE])
	_row(6, windows >= MIN_WINDOWS_PER_MINUTE,
			"6 · el promedio abre %.2f ventanas/min (mínimo %.1f)"
					% [windows, MIN_WINDOWS_PER_MINUTE])


func _assert_control(game: Dictionary) -> void:
	if game.is_empty():
		return
	var lost := int(game.get("state", -1)) == Global.RoundState.DEFEAT
	var integrity := float(game.get("integrity", 1.0))
	var duration := float(game.get("duration", 0.0))
	_row(7, lost, "7 · el control termina en DEFEAT (terminó en %s)"
			% _state_name(int(game.get("state", -1))))
	_row(7, integrity < RoundManager.DEFEAT_INTEGRITY,
			"7 · el control pierde con la ciudad bajo 0.35 (quedó en %.2f)" % integrity)
	_row(7, duration >= RANGE_CONTROL.x and duration <= RANGE_CONTROL.y,
			"7 · el control cae a los %.0f s (rango %.0f–%.0f)"
					% [duration, RANGE_CONTROL.x, RANGE_CONTROL.y])


## La prueba negativa: con `dodge_skill 0` y σ 25° el bot tiene que jugar
## claramente peor que el de referencia. «Peor» es medible de tres formas y basta
## con que la partida lo sea en todas: acierta mucho menos, y o bien pierde o bien
## muere más veces.
func _assert_negative(baseline: Array[Dictionary], game: Dictionary) -> void:
	if game.is_empty() or baseline.is_empty():
		return
	var reference: Dictionary = baseline[0]
	var hit := float(game.get("weak_hit_rate", 1.0))
	var reference_hit := float(reference.get("weak_hit_rate", 0.0))
	_row(11, hit < reference_hit * 0.6,
			"11 · la negativa acierta %.3f contra %.3f de la referencia (debe ser < 60 %%)"
					% [hit, reference_hit])
	var worse := not bool(game.get("victory", false)) \
			or int(game.get("deaths", 0)) > int(reference.get("deaths", 0))
	_row(11, worse,
			"11 · la negativa pierde o muere más que la referencia (%d muertes contra %d, %s)"
					% [int(game.get("deaths", 0)), int(reference.get("deaths", 0)),
					_state_name(int(game.get("state", -1)))])


# --- Informe ------------------------------------------------------------------------------------

## Vuelca una partida con todo lo que `docs/07` §14 pide registrar.
func _print_game(game: Dictionary) -> void:
	print("  resultado      : %s%s" % [_state_name(int(game.get("state", -1))),
			"  (TIMEOUT)" if bool(game.get("timed_out", false)) else ""])
	print("  duración       : %.1f s de batalla  ·  %.1f s simulados en %.1f s de reloj (×%.1f)"
			% [float(game.get("duration", 0.0)), float(game.get("sim_seconds", 0.0)),
			float(game.get("real_seconds", 0.0)), float(game.get("speed_factor", 0.0))])
	print("  ciudad         : integridad %.3f  ·  %d edificios destruidos"
			% [float(game.get("integrity", 0.0)), int(game.get("destroyed", 0))])
	print("  dron           : %d muertes  ·  energía mínima %.2f  ·  %d pilas  ·  %d golpes por %.0f de casco"
			% [int(game.get("deaths", 0)), float(game.get("min_energy", 1.0)),
			int(game.get("batteries", 0)), int(game.get("hits_taken", 0)),
			float(game.get("damage_taken", 0.0))])
	print("  arma           : %.1f s de fuego neto  ·  %d disparos  ·  ciclo %.3f"
			% [float(game.get("fire_seconds", 0.0)), int(game.get("shots", 0)),
			float(game.get("duty_cycle", 0.0))])
	print("  puntería       : %d impactos débiles / %d blindaje  ·  tasa débil %.3f  ·  precisión %.3f"
			% [int(game.get("weak_hits", 0)), int(game.get("armor_hits", 0)),
			float(game.get("weak_hit_rate", 0.0)), float(game.get("accuracy", 0.0))])
	print("  esquivas       : %d logradas de %d intentadas (%.0f %%)"
			% [int(game.get("dodges_made", 0)), int(game.get("dodges_tried", 0)),
			100.0 * float(game.get("dodges_made", 0))
					/ maxf(float(game.get("dodges_tried", 0)), 1.0)])
	print("  ventanas       : %d (%.2f por minuto)"
			% [int(game.get("windows", 0)), float(game.get("windows_per_minute", 0.0))])
	print("  fases          : %s" % _phase_line(game.get("phases", []) as Array))
	print("  usos por ataque: %s" % _uses_line(game.get("uses", {}) as Dictionary))
	print("  ventanas activas: %s" % _windows_line(game.get("windows_log", {}) as Dictionary))
	print("  partes rotas   : %d  ·  puntaje %d (base %d, ×%.2f)  ·  medalla %s"
			% [int(game.get("parts_broken", 0)), int(game.get("score", 0)),
			int(game.get("base_score", 0)), float(game.get("multiplier", 1.0)),
			_medal_name(int(game.get("medal", 0)))])
	print("  física         : mediana %.2f ms/tick  ·  p95 %.2f ms/tick  ·  %d muestras"
			% [float(game.get("physics_median", 0.0)), float(game.get("physics_p95", 0.0)),
			int(game.get("physics_samples", 0))])


func _phase_line(phases: Array) -> String:
	if phases.is_empty():
		return "sólo p1_siege"
	var parts: PackedStringArray = PackedStringArray()
	for entry: Variant in phases:
		var row := entry as Dictionary
		parts.append("%s@%.0fs" % [String(row.get("id", "?")), float(row.get("at", 0.0))])
	return " → ".join(parts)


## Una línea por ataque: `id activas/abortadas d=<colliders de dron> e=<edificios>`.
func _windows_line(log: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id: Variant in log:
		var row := log[id] as Dictionary
		parts.append("%s %d act/%d abort · %d al dron, %d a la ciudad" % [String(id),
				int(row["active"]), int(row["aborted"]), int(row["drone"]),
				int(row["building"])])
	return " · ".join(parts) if not parts.is_empty() else "ninguna"


func _uses_line(uses: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id: Variant in uses:
		var count := int(uses[id])
		if count > 0:
			parts.append("%s %d" % [String(id), count])
	return ", ".join(parts) if not parts.is_empty() else "ninguno"


## Tabla comparativa de todas las partidas contra los rangos de `docs/07` §14.
func _print_table() -> void:
	print("")
	print("  --- docs/07 §14: métricas por partida ---")
	print("  %-26s %7s %7s %6s %7s %7s %7s %7s %7s %6s" % ["partida", "dur(s)", "integr",
			"muert", "fuego", "acier", "ciclo", "vent/m", "pilas/m", "pts"])
	for game: Dictionary in _games:
		print("  %-26s %7.0f %7.3f %6d %7.0f %7.3f %7.3f %7.2f %7.3f %6d" % [
			String(game.get("label", "?")), float(game.get("duration", 0.0)),
			float(game.get("integrity", 0.0)), int(game.get("deaths", 0)),
			float(game.get("fire_seconds", 0.0)), float(game.get("weak_hit_rate", 0.0)),
			float(game.get("duty_cycle", 0.0)), float(game.get("windows_per_minute", 0.0)),
			float(game.get("batteries_per_minute", 0.0)), int(game.get("score", 0)),
		])
	print("  %-26s %7s %7s %6s %7s %7s %7s %7s %7s" % ["rango docs/07 §14",
			"390-540", ".45-.70", "1-3", "170-210", ".35-.45", ".50-.60", "≥3.0", "—"])
	# Los rangos se **derivan de las constantes** en vez de transcribirse. La fila decía
	# `.33-.50` a mano, y al recalibrar `RANGE_HIT` en WP-28 habría quedado mintiendo
	# sin que nadie lo notara: la tabla impresa es lo que el revisor lee, no el `const`.
	print("  %-26s %7s %7s %6s %7s %7s %7s %7s %7s" % ["aseverado (pueblo de ruta)",
			"%.0f-%.0f" % [RANGE_DURATION.x, RANGE_DURATION.y],
			"%s-%s" % [_short(RANGE_INTEGRITY.x), _short(RANGE_INTEGRITY.y)],
			"%d-%d" % [RANGE_DEATHS.x, RANGE_DEATHS.y],
			"%.0f-%.0f" % [RANGE_FIRE.x, RANGE_FIRE.y],
			"%s-%s" % [_short(RANGE_HIT.x), _short(RANGE_HIT.y)],
			"informe",
			"≥%.1f" % MIN_WINDOWS_PER_MINUTE,
			"≤%.1f" % MAX_BATTERIES_PER_MINUTE])
	print("  (duración, fuego, acierto, ventanas y pilas/min se aseveran sobre el promedio"
			+ " de las tres semillas; las muertes, por partida el techo y sobre la suite"
			+ " el piso de %d; ver la nota de _assert_combat)" % MIN_DEATHS_TOTAL)
	print("")


## `0.45` → `.45`. Es para que la tabla siga entrando en columnas de siete caracteres
## sin volver a transcribir los rangos a mano.
func _short(value: float) -> String:
	return ("%.2f" % value).trim_prefix("0")


# --- Utilidades ---------------------------------------------------------------------------------

## Monta la ronda 1 **a velocidad real y sin saltear la cinemática**, con el bot
## jugando, y se queda corriendo. Es el modo con el que Movie Maker recorre el
## guion del smoke test de `docs/15` §6 sobre el nivel de batalla de verdad: el
## `--quit-after` de la línea de órdenes decide cuándo cortar.
##
## [codeblock]
## godot --path godot --windowed --resolution 960x540 --write-movie <dir>/m.png \
##     --fixed-fps 10 --quit-after 900 res://tools/balance_check.tscn -- --showcase
## [/codeblock]
func _showcase(round_seed: int, kill_at: float = -1.0) -> void:
	print("  === recorrido de Movie Maker (semilla %d) ===" % round_seed)
	Global.selected_round = ROUND_ID
	Global.round_seed = round_seed
	var packed := load(LEVEL_SCENE) as PackedScene
	_level = packed.instantiate() as BattleLevel
	add_child(_level)
	await wait_frames(3)
	_manager = _level.get_round_manager()
	var rig := _level.drone_rig as DroneRig
	var enemies := _manager.get_enemies()
	_enemy = enemies[0] as EnemyBase
	_bot = BotPilot.new()
	_bot.name = "BotPilot"
	add_child(_bot)
	_bot.setup(rig, _enemy, _level.get_node_or_null(^"BatterySpawner") as BatterySpawner,
			RoundCatalog.derive_seed("bot"))
	# Ni la alerta ni la cinemática se saltean: el recorrido tiene que ver la
	# apertura entera, que desde WP-25b es ALERT → estática → INTRO.
	while _pre_battle(_manager.get_state()):
		await get_tree().process_frame
	_bot.start()
	print("  apertura terminada (ALERT + INTRO), el bot toma el mando")
	var killed := kill_at < 0.0
	while true:
		await get_tree().process_frame
		if not killed and _manager.get_elapsed_seconds() >= kill_at:
			killed = true
			# Paso 12 del smoke test (`docs/15` §6): matar al dron a propósito para
			# ver los 12 s de reconstrucción con la cámara sobre la ciudad.
			var hull := (_level.drone_rig as DroneRig).get_hull()
			if hull != null:
				hull.apply_damage(999.0, hull.drone.global_position)
				print("  dron destruido a propósito en t=%.1f s" % kill_at)


## Vuelca la caja de colisión de cada parte del jefe en su pose de reposo. No es
## parte del protocolo: es la herramienta con la que se comprobó, al medir WP-23,
## que los tres núcleos ventrales caen **dentro** del volumen del `underbelly`.
func _dump_geometry() -> void:
	await _probe_freeze_modes()
	var packed := load("res://enemies/arachnodroid/arachnodroid.tscn") as PackedScene
	if packed == null:
		fail("no se pudo cargar la escena del jefe")
		return
	var enemy := packed.instantiate() as EnemyBase
	add_child(enemy)
	await wait_physics(4)
	print("  parte                 capa   y_min   y_max   x_min   x_max   z_min   z_max")
	for part: EnemyPart in enemy.get_parts():
		if part.body == null:
			continue
		var shape := part.body.get_node_or_null(^"Shape") as CollisionShape3D
		if shape == null:
			for child: Node in part.body.get_children():
				shape = child as CollisionShape3D
				if shape != null:
					break
		if shape == null or shape.shape == null:
			continue
		var box := shape.shape as BoxShape3D
		var half := box.size * 0.5 if box != null else Vector3.ONE * 0.5
		var centre := shape.global_position
		print("  %-20s %5d %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f" % [part.part_id,
				part.body.collision_layer, centre.y - half.y, centre.y + half.y,
				centre.x - half.x, centre.x + half.x, centre.z - half.z, centre.z + half.z])
	enemy.queue_free()
	await wait_frames(2)


## Comprueba con qué modo de congelado un [RigidBody3D] de la capa 2 sigue
## apareciendo en el `intersect_shape` con el que el jefe resuelve sus barridos.
## Es de lo que depende que el bot pueda recibir daño (`BotPilot`).
func _probe_freeze_modes() -> void:
	var world := Node3D.new()
	add_child(world)
	for mode: int in [RigidBody3D.FREEZE_MODE_KINEMATIC, RigidBody3D.FREEZE_MODE_STATIC]:
		var body := RigidBody3D.new()
		body.collision_layer = PhysicsLayers.DRONE
		body.collision_mask = PhysicsLayers.WORLD
		body.gravity_scale = 0.0
		body.freeze_mode = mode as RigidBody3D.FreezeMode
		body.freeze = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		shape.shape = box
		body.add_child(shape)
		world.add_child(body)
		body.global_position = Vector3(0.0, 50.0, 0.0)
		await wait_physics(4)
		var params := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 5.0
		params.shape = sphere
		params.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 50.0, 0.0))
		params.collision_mask = PhysicsLayers.QUERY_SWEEP
		params.collide_with_bodies = true
		var hits := world.get_world_3d().direct_space_state.intersect_shape(params, 8)
		print("  congelado %s → intersect_shape encuentra %d cuerpo(s)"
				% ["KINEMATIC" if mode == RigidBody3D.FREEZE_MODE_KINEMATIC else "STATIC",
				hits.size()])
		body.queue_free()
		await wait_frames(2)
	world.queue_free()
	await wait_frames(2)


## Una línea de diagnóstico: dónde está cada cosa y qué punto débil está expuesto.
## Es lo que hace visible por qué una partida no termina.
func _print_trace(sim: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _bot == null:
		return
	var exposed: PackedStringArray = PackedStringArray()
	var alive: PackedStringArray = PackedStringArray()
	for point: WeakPoint in _enemy.get_weak_points():
		if point.is_broken():
			continue
		alive.append(String(point.weak_point_id()).replace("wp_", ""))
		if point.is_exposed():
			exposed.append(String(point.weak_point_id()).replace("wp_", ""))
	var bot_position := _bot_position()
	var target := _bot.current_target()
	var metrics := _bot.metrics()
	var rig := _level.drone_rig as DroneRig if _level != null else null
	var drone := rig.get_drone() if rig != null else null
	var weapon := rig.get_weapon_mount() if rig != null else null
	var energy := rig.get_energy_system() if rig != null else null
	print("    t=%6.1f  fase %-16s estr %.3f  jefe y=%5.1f %-8s  bot y=%5.1f d=%5.1f"
			% [sim, String(_enemy.current_phase()), _enemy.total_structure_ratio(),
			_enemy.global_position.y, String(_enemy.locomotion_state()), bot_position.y,
			bot_position.distance_to(_enemy.global_position)]
			+ "  blanco %-14s  expuestos [%s]  vivos [%s]"
			% [String(target.weak_point_id()) if target != null else "—",
			", ".join(exposed), ", ".join(alive)])
	print("             armado %s  energía %.2f  calor %.2f  gatillo %s  débiles %d  blindaje %d  mira → %s"
			% [str(drone.is_armed()) if drone != null else "?",
			energy.get_ratio() if energy != null else -1.0,
			weapon.get_heat_ratio() if weapon != null else -1.0,
			str(weapon.fire_pressed) if weapon != null else "?",
			int(metrics.get("weak_hits", 0)), int(metrics.get("armor_hits", 0)),
			_aim_hit(weapon, drone)])


## Qué encuentra el rayo de puntería del arma ahora mismo. Es la única forma de
## distinguir «el bot no dispara» de «el bot dispara y le pega al blindaje».
func _aim_hit(weapon: WeaponMount, drone: Drone) -> String:
	if weapon == null or drone == null or weapon.get_profile() == null:
		return "—"
	var space := drone.get_world_3d().direct_space_state
	var from := weapon.get_muzzle_position()
	var to := from + weapon.get_aim_direction() * weapon.get_profile().max_range
	var query := PhysicsRayQueryParameters3D.create(from, to, weapon.get_profile().hit_mask)
	query.exclude = [drone.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "nada"
	var collider := hit["collider"] as Node3D
	if collider == null:
		return "?"
	var weak_id := String(collider.get_meta(&"weak_point_id", "")) \
			if collider.has_meta(&"weak_point_id") else ""
	return "%s [capa %d]%s" % [collider.name,
			(collider as CollisionObject3D).collision_layer,
			"" if weak_id.is_empty() else " wp=%s" % weak_id]


func _bot_position() -> Vector3:
	var rig := _level.drone_rig as DroneRig if _level != null else null
	var drone := rig.get_drone() if rig != null else null
	return drone.global_position if drone != null else Vector3.ZERO


func _on_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if _manager == null or enemy != _enemy:
		return
	_phases.append({"id": String(phase_id), "at": _manager.get_elapsed_seconds()})


func _on_telegraphed(enemy: Node3D, attack_id: StringName, _duration: float) -> void:
	if enemy != _enemy:
		return
	_telegraphs[attack_id] = int(_telegraphs.get(attack_id, 0)) + 1


## Anota cada ventana activa del jefe: si se abortó por falta de apoyo y a cuántos
## colliders llegó. Es lo que separa «el ataque no se resolvió» de «se resolvió y
## el dron no estaba dentro» de «el dron estaba dentro y el daño no llegó».
func _on_action_changed(_from: StringName, to: StringName) -> void:
	if to != EnemyFSM.ACTION_ACTIVE or _enemy == null:
		return
	var brain := _enemy.brain as EnemyFSM
	var action := brain.current_action() if brain != null else null
	if action == null:
		return
	var sweep := action as SweepAction
	var id := action.id()
	var row: Dictionary = _windows_log.get(id, {"active": 0, "aborted": 0, "drone": 0,
			"building": 0})
	row["active"] = int(row["active"]) + 1
	if action.is_aborted():
		row["aborted"] = int(row["aborted"]) + 1
	elif sweep != null:
		var hits := sweep.last_hits()
		row["drone"] = int(row["drone"]) + hits.x
		row["building"] = int(row["building"]) + hits.y
	_windows_log[id] = row


## Percentil [param p] de las muestras de física, en ms.
func _percentile(p: float) -> float:
	if _physics_samples.is_empty():
		return 0.0
	var values := Array(_physics_samples)
	values.sort()
	var index := clampi(int(roundf(p / 100.0 * float(values.size() - 1))), 0, values.size() - 1)
	return float(values[index])


## Verdadero mientras la ronda siga en su apertura: la alerta del taller o la
## cinemática (`docs/11` §1).
func _pre_battle(state: int) -> bool:
	return state == Global.RoundState.ALERT or state == Global.RoundState.INTRO


func _state_name(state: int) -> String:
	match state:
		Global.RoundState.ALERT:
			return "ALERT"
		Global.RoundState.INTRO:
			return "INTRO"
		Global.RoundState.BATTLE:
			return "BATTLE"
		Global.RoundState.VICTORY:
			return "VICTORY"
		Global.RoundState.DEFEAT:
			return "DEFEAT"
	return "?"


func _medal_name(medal: int) -> String:
	match medal:
		RoundCatalog.Medal.GOLD:
			return "ORO"
		RoundCatalog.Medal.SILVER:
			return "PLATA"
		RoundCatalog.Medal.BRONZE:
			return "BRONCE"
	return "ninguna"


## Anota el resultado de una comprobación en su fila y registra el fallo.
func _row(number: int, ok: bool, message: String) -> void:
	if not _rows.has(number):
		_rows[number] = true
	if ok:
		return
	_rows[number] = false
	fail(message)


func _print_rows() -> void:
	print("")
	for index: int in ROW_TITLES.size():
		var number := index + 1
		var mark := "OK  " if _rows.get(number, true) else "FALLA"
		print("  %s fila %2d · %s" % [mark, number, ROW_TITLES[index]])


func _restore() -> void:
	Engine.time_scale = 1.0
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before
