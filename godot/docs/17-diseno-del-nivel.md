# 17 — Diseño del nivel: el pueblo de ruta

> Estado: borrador v1 · Fecha: 2026-09-22 · Gobierna: P2c (WP-T1…T4, WP-D1…D4) · Depende de: `docs/10-ciudad-destructible.md` (plano, `CityGrid`, destrucción), `docs/11-rondas-y-objetivos.md` (objetivo del jefe, marcadores), `docs/13-identidad-visual-y-audio.md` (identidad «Última luz»), `docs/narrativa/narrativa.md` §2 (el pueblo), `docs/pdfs/Level design processes and experiences` (Totten, ed.; teoría).

Este documento es el **cuaderno del level designer**: dice qué pueblo estamos construyendo, dónde está cada cosa y por qué, y qué nos falta para construirlo. Los tres documentos vivos que pide la teoría (mapa de densidad, master list de POI y directory) viven acá (§1, §2, §3). La verdad geométrica es `city/designs/town_a.json`; este documento la explica y la juzga. Cuando los dos difieran, gana el JSON y se corrige este documento.

## 0. Principios (de Totten, aplicados a un pueblo que se defiende desde un dron)

1. **El diseño se escribe a mano y el código lo resuelve.** La semilla no decide el trazado; decide giros de ±10 cm y tonos. Tocar la manzana 7 no mueve la 8.
2. **Hitos en pareja, siluetas distintas.** Tanque de agua elevado (vertical, calado, al noreste) y silo con galpón (macizo, al suroeste). Se ven desde los cuatro accesos, desde la ruta y desde el dron a 40 m de altura. Ningún hito compite con el jefe (22 m de huella, 30 m de alto): los hitos miden 14–18 m.
3. **Densidad no uniforme.** Un punto de interés cada 30–50 m en el pueblo, uno cada 300–500 m en el campo. El aburrimiento del campo es a propósito: es el «buffer» antes del límite jugable.
4. **Oposición pueblo/campo.** Adentro: cobertura, verticalidad, calles que tapan. Afuera: exposición, horizonte, el coloso se ve entero.
5. **Aproximación larga con revelado parcial.** Quien entra por la ruta ve primero el puente y la arboleda, después la estación de servicio (el «hola» del pueblo), después el tanque, y recién en la plaza ve la escuela. El coloso aparece de a pedazos entre las casas antes de mostrarse entero.
6. **Esquinas analógicas, nada de 90° perfectos.** La ruta cruza el pueblo a ~17° del eje; las transversales la cortan a 60–80°; las paralelas siguen a la ruta, no al mundo.
7. **Gramática consistente** (§4): el material dice qué hace la cosa. Chapa se rompe; hormigón cubre; toldo naranja = pila.
8. **Elección legible en cada cruce.** Desde cualquier nodo se ven dos opciones distintas: la avenida abierta o la calle sombría con árboles.
9. **Repetición con variación.** Seis casas base × color × medianera × patio × árbol × estado. Una sola casa con la puerta abierta, y es la que cuenta la historia.
10. **Historia ambiental.** Todo lo que está fuera de lugar responde a «¿qué pasó los últimos veinte minutos?»: autos apuntando hacia afuera, ropa tendida, sillas en la vereda, una manguera cortada, un triciclo volcado en la plaza.
11. **Pases separados** (§5): trazado → juego → arte → pulido. No se pinta antes de que el trazado pase los checks.

## 1. Mapa de densidad por anillos

Anillos medidos desde `play_centre` (0, 0). El círculo jugable mide 140 m; el disco de manzanas 180 m (los vértices llegan a r 166 m); el terreno se desvanece a la cota 0 entre 230 y 256 m.

| Anillo | Radio | Qué hay | POI/ha objetivo | Destructible | Función de juego |
|---|---|---|---|---|---|
| 0 · corazón | 0–60 m | plaza con mástil, monumento y bancos; escuela enfrente (oeste); las cuatro manzanas más densas (8, 9, 2, 3); la avenida (ruta) con cordón y farolas | 1 / 30 m | sí | objetivo del jefe, arena central, cobertura entre casas |
| 1 · barrio | 60–140 m | ocho manzanas de casas con patios; estación de servicio sobre la ruta (manzana 6); tanque de agua (manzana 5, noreste); silo y galpón (suroeste, fuera de las manzanas); cuatro puestos de pila bajo toldo naranja | 1 / 50 m | sí | el 80 % del daño urbano; los cuatro accesos del jefe |
| 2 · borde | 140–230 m | caserío (12 casas crudas), arboleda del arroyo, puente, cercos de alambre, tranqueras que cierran las calles que salen, cartel de bienvenida, señal de la ruta | 1 / 150 m | no | límite legible del área; el jugador entiende «hasta acá» sin muro |
| 3 · campo | 230–600 m | ruta con banquina, lomas suaves, maizales en dos etapas, un molino, alambrado, el arroyo que se aleja | 1 / 400 m | no | buffer aburrido; horizonte para leer al coloso entero |

Reglas que verifica `city_check` (fila «densidad por anillo», WP-D4): la cuenta de POI por anillo queda dentro de ±30 % de la columna «POI/ha objetivo» convertida a cantidades (anillo 0: 4–7; anillo 1: 14–22; anillo 2: 8–14; anillo 3: 4–8).

## 2. Master list de puntos de interés (POI)

Coordenadas en metros, marco del nivel (x al este, z al sur; el norte es −z). Son objetivos de diseño con ±10 m de tolerancia hasta que el JSON las fije; la columna «estado» sigue el tablero de §5.

| id | Qué es | Pos. aprox. | Huella | Rol / pieza | Silueta | Desde dónde se ve | Historia que cuenta | Estado |
|---|---|---|---|---|---|---|---|---|
| `school` | Escuela 12 (protegida, objetivo del jefe) | (−28, −10), manzana 8, fachada al este sobre la calle 4 | 20 × 11 m, 2 plantas | `school` / `tower_b` ×1,15 | bloque bajo y largo con mástil | plaza, ruta a 60 m, calle 4 | ventanas con cartulinas, bicicletas contra la reja, el mástil con bandera a media asta (la puso alguien esta tarde) | sembrada (D2) en m08 (−11,9; −15,8), fachada al este alineada con el mástil de la plaza |
| `plaza` | Plaza central | manzana 9 entera (centroide (25, 6)) | ~45 × 40 m | `plaza` (polígono) | vacío rodeado de árboles | ruta, calles 4 y 5 | bancos, un triciclo volcado, la fuente seca, farolas | sembrada (D2): losa + cantero, mástil, monumento, 6 bancos, 4 faroles, 8 árboles, parada; sin triciclo ni fuente (piezas que faltan) |
| `monument` | Monumento y mástil de la plaza | (25, 4) | 4 × 4 m | prop procedural | vertical fino | plaza | placa; el mástil es el eje de la plaza | pendiente (D1) |
| `gas_station` | Estación de servicio «el hola» | manzana 6 (centroide (−129, −42)), sobre la ruta | marquesina 24 × 14 m + tienda 12 × 8 m | `gas_station` (marquesina procedural + `shop_a`) | techo plano flotante sobre 4 columnas, cartel alto | ruta desde el puente (250 m), calle 1, todo el sur | dos autos cargando, uno con la puerta abierta; el cartel de precios apagado | sembrada (D1/D2) en m06 (−120,7; −54,3), pila 4 bajo su toldo |
| `water_tower` | Tanque de agua elevado (hito A) | (135, −20), manzana 5 | 8 × 8 m, 16 m de alto | `water_tower` (procedural) | cilindro sobre 4 patas con escalera; calado | los 4 accesos, ruta, dron | pintado con el nombre del pueblo; goteo | sembrado (D1/D2) en m05 (135, −20), 16,5 m; visible desde los 5 ojos |
| `silo` | Silo con galpón (hito B) | (−95, 70), lote rural al sur de la paralela 9 | silo Ø 6 × 14 m; galpón 18 × 10 m | `silo` + `shed` (procedurales) | cilindro macizo con cono | los 4 accesos, ruta, dron | camión de cereal estacionado, tolva a medio cargar | sembrados (D1/D2): silo (−95, 70) y galpón (−74, 76) rurales con `pickup` y `truck` placeholder |
| `bridge` | Puente sobre el arroyo | (−183, −84), ruta, cruce a 75° | 16 m de vano, 12 m de tablero | `bridge` (procedural) | tablero bajo con barandas | ruta oeste (400 m), arboleda | el guardarraíl abollado; la señal de «puente angosto» | pendiente (D1/D2) |
| `creek_grove` | Arboleda del arroyo | banda r 200–222 m, noroeste | ~293 m de largo | `groves` (Foliage: sauces = `tree_large` y `tree_xl`) | masa oscura baja | ruta, norte del pueblo | sombra, límite natural del norte | pendiente (D2) |
| `welcome_sign` | Cartel de bienvenida | (−215, −70), sur de la ruta, antes del puente | 4 × 0,3 m, 3 m de alto | prop procedural (atlas nuevo) | vertical plano | ruta oeste | el nombre del pueblo y «Escuela 12 · 1,2 km» | pendiente (D1) |
| `gate_n1` … `gate_n4` | Tranqueras que cierran las calles que salen del disco | cabos de las calles 1, 7, paralela 8 oeste y paralela 9 este | 6 m | `closure: gate` | horizontal baja | cada cabo | «el pueblo termina acá»; alambrado hacia el campo | pendiente (T1/T3) |
| `battery_1` … `battery_4` | Puestos de pila bajo toldo naranja | esquinas de las manzanas 2, 4, 7, 10 | 3 × 3 m | marcador `battery` + toldo (`awning` del pack city) | franja naranja | desde la calle a 60 m | kiosco, parada de colectivo, garita: la pila siempre está bajo naranja | pendiente (D2) |
| `open_door_house` | La única casa con la puerta abierta | manzana 3, frente a la ruta | casa base | `house_c`, `door_open: true` | — | ruta, plaza | adentro se ve la mesa puesta; ropa tendida en el patio | pendiente (D2) |
| `windmill` | Molino de campo | (250, 190), sureste, campo | 3 × 3 m, 12 m de alto | `windmill` (procedural o conseguir) | rueda calada | ruta este, dron | gira despacio; único movimiento del campo | pendiente (D1) |
| `hamlet_w` / `hamlet_e` | Caseríos del borde | 6 casas al oeste (r 160–200) y 6 al este (r 160–210) | casas base crudas | `decor_houses` | — | ruta | quintas con cercos de alambre y árboles frutales | existentes (P2b), reubicar (D2) |
| `cornfield_s` | Maizales | sur, r 260–450 | dos parcelas de ~120 × 80 m | `foliage` (Foliage: maíz etapas 2 y 4) | textura baja | dron, ruta | la cosecha a medias; huellas de tractor | pendiente (D1/D2) |

Reglas de visibilidad (fila «hitos visibles» de `city_check`, WP-D4): desde cada `EnemySpawn` y desde `DroneSpawn`, el tanque y el silo subtienden ≥ 0,8° verticales y ningún terreno ni edificio de altura > 6 m los tapa (raycast al tercio superior del hito).

## 3. Directory por locación

Cada locación se describe con: propósito de juego, qué la delimita, qué se ve desde ahí, qué props la cuentan, qué la conecta.

- **Plaza y escuela (anillo 0).** Es el objetivo y el escenario del final. La plaza es la única manzana sin casas: da línea de tiro larga (45 m) en las dos diagonales y deja ver la escuela entera desde la ruta. La escuela mira a la plaza a través de la calle 4 (9 m + veredas de 3 m); el mástil de la plaza y el de la escuela se alinean con el eje de la calle. Árboles medianos en el perímetro de la plaza (no en el centro: el jefe tiene que poder pararse ahí y el jugador leerlo). Bancos, farolas, el triciclo. Conecta con la ruta (norte), calle 4 (oeste), calle 5 (este), paralela 9 (sur).
- **Avenida (la ruta dentro del pueblo).** 10 m de calzada, 3 m de banquina que dentro del pueblo se vuelve vereda con cordón y farolas cada 25 m. Es la única calle con marcas viales (`roads.tres`). Corta el pueblo a ~17°: desde un extremo no se ve el otro (hay un quiebre en (−164, −83) y otro en (224, 36)), así que el coloso que viene por la ruta se revela en el quiebre.
- **Manzanas de casas (anillo 1, manzanas 0–4, 7, 8, 10, 11).** Cuatro a seis casas por manzana con frente a la calle de mayor jerarquía (ruta > calle > pasaje), patios hacia adentro con árbol frutal y tendedero, medianeras compartidas donde dos casas se tocan. Cordón y vereda solo en los lados con calle; los lados sin calle terminan en cerco de alambre y pasto. Variación: 6 piezas × 4 colores × 3 estados (`intact`, `weathered`, `abandoned`) × jardín sí/no × árbol (`tree_small`/`tree_medium`/ninguno) × cerco (`picket`/`wire`/`none`). Regla: dos casas vecinas nunca repiten pieza + color.
- **Estación de servicio (manzana 6, entrada oeste).** Marquesina plana sobre cuatro columnas, dos surtidores, tienda de 12 × 8 m con toldo naranja (**puesto de pila 4**), playón de hormigón que sale a la ruta por dos bajadas de cordón. Dos autos, uno con la puerta abierta. Es lo primero que se ve al entrar y lo primero que el jefe puede romper: la marquesina cae en una pieza (`state` 2 = marquesina en el piso).
- **Tanque de agua (manzana 5, noreste).** Sobre el punto más alto del pueblo (+2,5 m sobre la cota de la plaza; el `datum` de la manzana 5 se fija a mano). Cuatro patas de hormigón, tanque cilíndrico de chapa, escalera. Al derrumbarse deja el charco (decal) y las patas. Alrededor: un lote vacío con pasto alto y el alambrado.
- **Silo y galpón (lote rural, suroeste).** Fuera de las manzanas pero dentro del círculo: destructible. El silo (Ø 6, 14 m, cono) y el galpón de chapa (18 × 10, techo a dos aguas) con el camión de cereal. Sin vereda: entrada de ripio desde la paralela 9 por una tranquera abierta. Contrapone al tanque: macizo contra calado, sur contra norte.
- **Arroyo, puente y arboleda (anillo 2, noroeste).** El arroyo cruza la ruta bajo el puente a 201 m del centro (cruce a 75°) y corre por el norte del pueblo a 200–222 m, entre sauces grandes, con 6,6 m de holgura mínima a los cabos de las calles. Es el borde natural del norte: desde las manzanas 0 y 1 se ve la línea oscura de árboles. Cauce de 6 m, 2,4 m de profundidad, bancos de 9 m; el agua es un plano con shader simple (D3). El puente: tablero de hormigón de 12 m de ancho, barandas de caño, señal de «puente angosto» 40 m antes.
- **Caseríos (anillo 2, este y oeste).** Doce casas crudas (sin `building.gd`); seis de ellas en quintas de 14 × 14 m con cerco de alambre girado al rumbo de la casa y un árbol grande (el tanque australiano sigue en la lista de assets que faltan). Están a 160–210 m: se ven, no se rompen, y le dan escala a la salida del pueblo.
- **Campo (anillo 3).** Lomas de ±3,5 m con grano fino, la ruta con banquina de ripio, alambrado cada 300 m siguiendo la ruta, dos maizales al sur, el molino al sureste, el arroyo que se aleja al norte. Nada que llame la atención: es el fondo sobre el que se lee la silueta del coloso.

## 4. Gramática visual (material → afordancia)

| Se ve | Significa | Regla de construcción | Verificado por |
|---|---|---|---|
| chapa (gris, ondulada) y ladrillo visto | se rompe (destructible) | todo `Building` dentro del círculo usa las familias Nuke con overlay de daño | `city_check` conteo por rol |
| hormigón liso (columnas de la marquesina, patas del tanque, tablero del puente, cordones) | cubre y no se rompe primero | las piezas de hormigón son las últimas etapas de daño (quedan en pie como ruina) | `city_check` etapas |
| **toldo naranja** | hay una pila | los 4 marcadores `battery` están bajo un toldo naranja y no hay toldo naranja sin pila | `city_check` fila «toldo = pila» (WP-D4) |
| asfalto con marcas | ruta: rápido, expuesto | solo la ruta lleva marcas (`roads.tres`); calles y pasajes van lisos (`ASPHALT_UV`) | `city_check` `_expect_marks_along` |
| vereda gris con cordón de 15 cm | borde de manzana con calle | anillos `RoadMesh.ring` solo en lados con calle | `city_check` «veredas continuas con cordón» |
| alambrado y tranquera | límite del área jugable | toda calle que sale del disco termina en `closure: gate`; el círculo de 140 m se lee por los cercos, no por un muro | `city_check` «0 cabos sueltos» |
| árboles grandes en masa | agua cerca (arroyo) | `groves` solo sobre la banda del arroyo y en la plaza | diseño (revisión) |
| luz ámbar de ventana | gente (identidad «Última luz») | ventanas racionadas 5 de 12 manzanas, ámbar | `docs/13` |
| luz cian | máquina | solo el jefe y el HUD | `docs/13` |

## 5. Tablero de pases

| Pase | Qué se decide | Quién | Entrega | Estado |
|---|---|---|---|---|
| 1 · trazado | grafo de calles, manzanas, nodos, cabos cerrados, cotas por manzana, terreno base, arroyo y puente | orquestador (JSON) + WP-T1/T2/T3/T4 | `town_a.json` de andamio + viario + terreno; `city_check`, `terrain_check`, `town_plan_check` en verde | en curso (tanda 1) |
| 2 · juego | plaza abierta, líneas de tiro, cobertura por manzana, 4 accesos del jefe, puestos de pila bajo toldo, hitos visibles, densidad por anillo | orquestador (JSON bueno) + WP-D2 | `town_a.json` definitivo; `balance_check` recalibrado | pendiente (tanda 2) |
| 3 · arte | piezas nuevas (packs + procedurales), materiales del terreno, luz, niebla, arboleda, maizales, agua | WP-D1 + WP-D3 | `assets/town/**`, `assets/city/terrain/**`, capturas desde los tres encuadres | pendiente (tanda 2) |
| 4 · pulido | historia ambiental (autos, ropa, sillas, triciclo, manguera), variación de casas, carteles, señales, farolas | WP-D2/D3 | JSON `props` + `story` | pendiente (tanda 2) |

Los tres encuadres de revisión (se capturan en cada checkpoint con `tools/town_showcase.gd`): **ruta a 120 m** del puente mirando al pueblo (revelado: puente, arboleda, estación, tanque), **plaza a 60 m** de altura (escuela, plaza, avenida, las cuatro manzanas del corazón), **entre casas a 4 m** (cordón, vereda, cercos, patios, una casa con la puerta abierta).

## 6. Hechos medidos

> (Se completa al cerrar cada WP; el orquestador anota aquí lo que los checks midieron: lotes, `physics_tick_ms`, pendientes, conteos por anillo, tamaño del `.tscn`.)

- 2026-09-22 · **Punto de partida (P2b)**: `town_a.tscn` 356 KB con las mallas embebidas; 12 manzanas, 46 casas + 5 medianos + hito + escuela = 53 destructibles, 84 300 HP; `render_check` HIGH 712 lotes; `physics_tick_ms` de referencia 1,27 ms (`docs/perf/2026-09-20-p2.json`). Defectos del viario diagnosticados: cruces como parche cuadrado alineado al mundo y coplanar (z-fighting), veredas que atraviesan cada cruce, transversales 1 y 7 amputadas por `_clip_to_circle(172)`, paralelas colgando 12–52 m, cabos de 7–17 m sin cerrar, muescas en los quiebres de la ruta, `BlockPads` en rejilla del mundo (escalera de 5 m, losas salientes de 18 cm).
- 2026-09-22 · **Tanda 1 (WP-T1/T2/T3)**: diseño de andamio en `town_a.json` (23 nodos, 10 calles, 14 cabos con tranquera, 12 manzanas, 46 casas, `block_radius` 180) que reproduce P2b a 0,72 mm y corrige en el diseño las dos transversales amputadas y las dos paralelas colgantes; ángulo mínimo entre bocas 74,5°. Viario del plano resuelto: 21 cruces con polígono, 430 tris de asfalto y 1 032 de vereda, 0 coplanares, cordón 0,15 m. Terreno 513² a 1 m: alturas −5,5…3,6 m, ruta con gradiente ≤ 1,85 %, manzanas planas al milímetro, arroyo r 200–222 m con holgura 6,57 m a los cabos y puente a 75°; heightfield sin coste medible (0,686 ms/tick), 4/2/1 lotes por vista. Pendiente: el pie del jefe pivota hasta 0,43 m sobre relieve (IK al tobillo).
- 2026-09-22 · **WP-T4 (integración)**: suite completa en verde (32 pasos). `town_a.tscn` 309,8 KB; `render_check` HIGH máx 714 (presupuesto 860); `physics_ms_avg` 1,90 contra 1,903 de referencia (plano; el «≤ 1,40» del criterio 11 no correspondía a ninguna métrica: pasa a «sin regresión ±10 %»). Ruta exterior como cinta entera (las baldosas se enterraban y flotaban en el anillo de desvanecido). Casas apoyadas: peor esquina 12,4 mm. Capturas revisadas por el orquestador (`tools/out/shots/town_showcase/`): calle a 4 m correcta (cordón, veredas, casas apoyadas, peralte creíble); plaza con trazado limpio y tranqueras, pero **muesca periódica en el borde de las veredas** y ventanas ámbar quemadas en picado; aérea con el **relieve interior ilegible** (plano azul oscuro sin sombreado) y **arista recta de tono a 260 m** contra el anillo exterior; desde la ruta el arroyo no cruza (máscara civil) y el campo lejano se lee como lámina celeste. `Decor_House_04/05` dentro del arroyo y `_00` sobre la banquina. Todo eso va a WP-T5 (cierre corto) antes del checkpoint; puente y arboleda son D1/D2; tono, glow y SDFGI son D3.
- 2026-09-22 · **WP-T5 (cierre corto)**: el relieve no se veía porque los chunks estaban cosidos al revés (`cull_back`); la arista a 260 m y la lámina celeste eran el agujero del campo lejano. Paleta del terreno corregida (tierra, roca y lecho por encima del pasto; tierra urbana 0,33). La muesca de las veredas era el cordón pintado del atlas estirado sobre la calzada: la ruta conserva marcas, calles y pasajes van lisos. Off-by-one de cabos corregido (holgura del arroyo 9,69 m). Tres caseríos fuera del arroyo y de la banquina (pads de ~7,2 m de radio: regla ≥ 8,5 m de la franja de calle). Capturas verificadas por el orquestador: relieve continuo con lomas sombreadas y el arroyo como banda clara, sin arista; ruta sobre suelo continuo hasta el horizonte; veredas con borde liso; calle a 4 m correcta. **Listo para el checkpoint.** Para D3: patios de manzana oscuros en sombra al anochecer, ventanas ámbar quemadas en picado, campo oscuro a ángulo rasante; para D4: fila «los chunks miran al cielo», solape 256–260 m, `_load_spec` que falle fuerte; para D1: puente con el arroyo bajo la ruta, arboleda; nits de caseríos 01/03/06/07/11.
- 2026-09-23 · **WP-D1 (ingesta y procedurales)**: 54 piezas en el manifiesto (14 edificios, 29 props, 11 follaje) verificadas por `town_import_check` a 0,0 % de desvío; follaje reescalado a la escala del pueblo (árboles de 8,5–11,75 m contra casas de 3 m; capturas revisadas por el orquestador: la escalera de siluetas se lee, el toldo naranja es inequívoco, los vehículos son placeholders evidentes, el hormigón procedural es un gris moteado que D3 puede afinar). `chapel` fuera por las dos paletas del VillagePack. Vano del puente abierto en el terreno (2,12 m) y `terrain_check` con 14 filas. El acceso oeste del jefe coincidía con el vano: el cruce del arroyo pasa a arco −230 m.
- 2026-09-23 · **WP-D2 (pase de diseño)**: el pueblo de §2–§3 horneado. POI finales: escuela en m08 (−11,9; −15,8) mirando a la plaza (alineada con el mástil, no en (−28, −10)); plaza = m09 (1 779 m²); estación en m06 (−120,7; −54,3); tanque en m05 (135, −20) en medio del lote; silo (−95, 70) y galpón (−74, 76) rurales; `mid_0` → m10 (borde este de la plaza), `mid_2` → frente de la calle 4 de m03; puente a arco −230 m (−212,7; −83,8). 41 casas, 52 destructibles, 91 800 HP, 1 414 árboles/matas, 286 tramos de cerco, 75 props, densidad por anillo 7/16/9/7. `render_check` 857/860: margen de 3. Capturas revisadas por el orquestador: el revelado desde la ruta funciona (arboleda a los lados, marquesina blanca al fondo), la plaza con la escuela enfrente se lee; **para D3**: follaje verde saturado fuera de paleta, cantero y patios casi negros, hormigón procedural moteado, ventanas quemadas en picado, agua del arroyo, alambrado del disco demasiado circular desde el aire, pad rural espejado en `build_terrain`, margen de lotes.
- 2026-09-23 · **WP-D3/D3b (arte y legibilidad)**: los 10 puntos medidos y cerrados salvo la niebla (no aplicada: los números dicen que empeora) y `props.tres` (decisión pendiente: emisión neón magenta que compite con los núcleos del jefe). Follaje 0,80× fachada, cantero 0,73× losa, hormigón sd 0,030, ventanas 0,00 % quemadas, agua con 2,33 m de aire bajo el tablero, `render_check` **801** (margen 59), alambrado quebrado, farol ámbar, pad rural corregido. Capturas revisadas por el orquestador: la plaza con la escuela enfrente y el cantero verde se lee; el revelado desde la ruta con arboleda oliva funciona; desde el aire el disco de alambrado ya no es un compás; queda una duda sobre unos contornos naranjas junto a la estación (a la revisión).
- 2026-09-23 · **Revisión de código y WP-D4a**: 30 hallazgos, 28 corregidos. El bloqueante era el cabo aplicado dos veces (tranqueras al doble); cinco cabos eran más cortos que la boca de su cruce y suben a radio + 0,5 m. Cambios de trazado que salieron de las filas nuevas: estación corrida 6,47 m dentro de m06 y tanque 2,08 m (huella entera dentro de 140 m), casa dañada de m00 a 9 m, caseríos 04 y 06 corridos por las quintas (ahora giradas al rumbo de la casa, en alambre, separadas ≥ 2 m). Los carteles de neón de la ciudad no entran al pueblo. `render_check` 793; `.tscn` reproducible. Capturas revisadas por el orquestador (aérea): tranqueras en la punta de cada calle, quintas sin cuadrícula, sin neón, viario gris-lila sin salmón. Abierto: contraste de valor vereda/calzada 0,97× (pide un parche más claro del atlas), troncos naranjas del follaje desde el aire.

## 7. Lista de assets: tenemos, faltan, decidimos

### 7.1 Tenemos y sirven (en `assets/_raw/`, sin licencia resuelta: ver `docs/16`)

| Pack | Qué usamos | Notas |
|---|---|---|
| `nuke Free Sample.zip` (ya remallado en `assets/town/`) | 6 casas base, 5 medianos, hito, carteles con emisión | voxel 0,05 m; en uso desde P2b |
| `Foliage.rar` | árboles XL/grande/medio/chico, tocón, 4 arbustos, pastos, flores, maíz en 4 etapas, 4 rocas | 32 modelos, 4 682 tris en total, voxel 0,1 m; clase `foliage` sin colisión para `MultiMesh` |
| `VoxelVillagePack.zip` | farol de 3 m (76 tris), cerco de 1,2 m, puente de madera 6 × 3 × 4 (pasarela peatonal del arroyo), barril, cajones, 2 rocas; 4 edificios extra solo en `village.vox` (uno de 4 × 4 × 6 m: candidato a capilla/campanario) | voxel 0,1 m; 12 personas de 1,6 m (no se usan: no hay gente en el nivel) |
| `city-Free Sample.zip` | esquina de vereda 5 × 5, bloques apilables de 2,5 m, parada de colectivo, dos toldos de tela (**el toldo naranja de las pilas**) | voxel 0,05 m; piezas sin centrar (corregir en la receta) |
| `Package.zip` | barrancas de 4 m | 5–17 k tris cada una: uso marginal (una o dos en el arroyo, si el presupuesto lo permite) |
| **Procedurales propios** (`tools/build_town_props.gd`, WP-D1) | estación de servicio, tanque de agua, silo, galpón, poste de luz, banco, mástil, monumento, cartel de bienvenida, señales, poste y tramo de alambrado, tablero del puente, cuatro vehículos **placeholder** | 18 piezas, 2 868 tris; atlas `signs.png` propio; determinista |

### 7.2 Necesitamos y NO tenemos (conseguir o modelar)

Prioridad A = sin esto el nivel no se lee como se diseñó; B = mejora clara; C = deseable.

| Prioridad | Asset | Para qué | Decisión provisional |
|---|---|---|---|
| **A** | **vehículos**: 2–3 autos, una camioneta, un camión de cereal, un colectivo | historia ambiental (autos hacia afuera, estación, silo), escala humana | **no hay en ningún pack**; conseguir un pack voxel de vehículos con licencia clara. **Provisional (WP-D1)**: `car_a`, `car_b`, `pickup`, `truck` procedurales con `placeholder: true` |
| ~~A~~ | surtidor + marquesina de estación | POI `gas_station` | **hecho (WP-D1)**: `gas_station` procedural 17,7 × 25,4 × 8 m con 4 surtidores, cartel y toldo |
| ~~A~~ | tanque de agua elevado | hito A | **hecho (WP-D1)**: `water_tower` 16,5 m, 622 tris |
| ~~A~~ | silo con cono | hito B | **hecho (WP-D1)**: `silo` 14 m |
| ~~A~~ | alambrado de campo (postes + 3 alambres) y tranquera | límite del área, cierres de cabo | **hecho**: tranquera y alambrado de cabo por `RoadMesh.closure` (WP-T1); `fence_post` y `fence_wire_6m` para polilíneas (WP-D1) |
| ~~A~~ | cartel de bienvenida y señales de ruta (puente angosto, velocidad, cruce) | legibilidad de la entrada | **hecho (WP-D1)**: `welcome_sign`, `road_sign_narrow`, `road_sign_speed` con atlas `signs.png`; falta la señal de cruce |
| ~~B~~ | galpón de chapa a dos aguas | lote del silo | **hecho (WP-D1)**: `field_shed` 10,6 × 18,6 × 6 m |
| ~~B~~ | poste de luz con brazo (avenida) | ritmo de la ruta cada 25 m | **hecho (WP-D1)**: `lamp_post` 8,2 m; `lantern` de 3 m para la plaza (sin emisivo: nota para D3) |
| ~~B~~ | puente vehicular de 12 m de tablero | POI `bridge` | **hecho (WP-D1)**: `bridge_deck` 20 × 12 m con barandas y estribos; la pasarela de madera del VillagePack no se ingirió |
| **B** | alcantarilla de hormigón | cierres de cabo `culvert`, cruces de zanja | procedural |
| ~~B~~ | bancos de plaza, mástil, monumento | plaza | **hecho (WP-D1)**: `bench`, `flag_mast` (bandera a media asta), `monument` («MEMORIA») |
| **B** | capilla | silueta del corazón (opcional, si la plaza queda vacía de un lado) | recomponer desde `village.vox` (edificio de 4 × 4 × 6 m, 1 604 tris): **bloqueada** porque el VillagePack trae dos paletas y el compositor exige una; pendiente de fundir paletas |
| **C** | molino de campo | anillo 3 | procedural (rueda calada + torre) o conseguir |
| **C** | mobiliario suelto (sillas de escuela, mesas, tendedero, triciclo, manguera) | historia ambiental | procedural mínimo o conseguir un pack de props domésticos |
| **C** | tanque australiano | quintas de los caseríos | procedural (anillo de chapa) |
| ~~C~~ | agua del arroyo (shader) | POI `creek` | **hecho (D3)**: `city/creek_water.gdshader`, cinta sobre el cauce, 1 lote |

### 7.3 Decisiones sobre los packs

- **Choque de resolución** (0,1 m de Foliage/Village contra 0,05 m de Nuke/city): se acepta como estilo (vegetación y mobiliario más gruesos que la arquitectura); si en las capturas a 4 m se nota, se revoxeliza la vegetación a 0,05 en la receta (`objvox` admite el factor).
- **Nada se commitea sin procedencia**: cada pack nuevo entra en `docs/16` y en `assets/town/LICENSE-PENDING.md` antes del commit; lo que no se pueda acreditar se reemplaza por procedural.
- **Las personas del VillagePack no se usan**: el pueblo está evacuado; la gente se cuenta con luz ámbar y objetos, no con figuras.
