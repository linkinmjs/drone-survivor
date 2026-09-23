# 10 — Ciudad destructible

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-13 y WP-20 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/06-framework-de-enemigos.md`, `docs/08-combate-y-armas.md`, `docs/09-energia-y-danio.md`

## 1. Objetivo y alcance

> **Nota del cierre de la revisión de la tanda 2 de P2c (2026-09-23, hechos medidos)**: revisión de solo lectura (`godot-code-reviewer`) con 1 bloqueante, 11 importantes y 18 menores, corregidos por WP-D4a salvo dos excluidos a propósito (las arboledas no cuentan en la visibilidad de hitos, regla escrita de `docs/17` §2; y los retornos ignorados con nombre descriptivo quedan). **Bloqueante**: el cabo de cada calle se aplicaba **dos veces** (el resolvedor lo hornea dentro del eje en `build_graph` y `_emit_roadways`/`_emit_closures` lo volvían a sumar): las 14 tranqueras estaban al doble (15,6–33,6 m), el último tramo de asfalto apoyaba sobre relieve no aplanado y `terrain_check` estiraba el corredor 2× mientras `city_check` medía 1×; ahora `clip_ribbon_at_nodes(axis, cuts, 0, 0)`, cierres en `0`/`total`, los dos corredores unificados en 1× y una fila nueva «cabos a la distancia declarada» (punta del asfalto y cierre a 0,00 m del nodo + `street_stub_of`, tope 0,30). La fila destapó que **cinco cabos eran más cortos que el radio de boca de su cruce** (el polígono seguía hasta 3,3 m más allá de la tranquera): suben a radio + 0,5 m en el JSON; la holgura del arroyo pasa a 15,67 m contra la calle 0. **Importantes**: `TownPlan.signature()` cubre ahora giros y escalas de arboleda, giros de cerco y `on_terrain` de los props (fila «la firma ve»: 5 cambios de un solo valor sobre 204 líneas de firma); `CityGrid._rng` secuencial reemplazado por `mix_unit(mix_all([SALT, parcela, canal]))` (agregar un POI ya no re-sortea carteles ni rocas); **`town_a.tscn` byte a byte reproducible** (`_stabilise_ids` en `build_town.gd` reescribe los 107 `id=` de `ext_resource`, 68 de `sub_resource` y 393 `unique_id=` desde el `path`/orden/`NodePath` con splitmix64; md5 idéntico en dos horneados); los tres toldos naranja con `lift 2,4` y el puesto de pila de calle a 2,8–3,2 m (antes 4–6 m sobre un toldo apoyado en el suelo), fila «toldo = pila» en 3D (el más lejano a 3,50 m); POI rurales sin `SIDEWALK_TOP` (silo y galpón a 0,0 mm); `visibility_range_end_margin` 20 m con `FADE_SELF` (el recorte es por nodo, no por instancia) y `city_check._decor_lots` modela el recorte por nodo entero con el AABB reconstruido desde el búfer del `MultiMesh` (`get_aabb()` devuelve vacío en `--headless`, la fila estaba ciega); los maizales quedan enteros (partirlos metía las mitades norte dentro del alcance y subía 9 → 11 lotes); tablero del puente con el cabeceo del vano (`bridge_deck_xform`, −0,39°) y cota de `route_height_fn` en el centro, fila «tablero contra calzada» a 0,0 mm; **círculo de juego por huella entera** (antes por el centro): la estación (huella real 25,4 × 17,7) se corre 6,47 m dentro de m06 (peor esquina 139,80 m), el tanque toma su huella real y se corre 2,08 m (139,76; sigue visible desde los cinco ojos), la casa dañada de m00 a 9,00 m de ancho (139,9); quintas del caserío giradas al rumbo de su casa, separadas ≥ 2 m (2,06–2,28 por SAT), en **alambre** (como dice `docs/17` §3) y con el cerco de tabla repintado a madera gris (118, 104, 86) para no competir con el naranja; **los props de ciudad (`sign_*`, `dish`, `props.tres` neón) no entran al pueblo** (`prop_pieces = []`; un cartel de neón sobre un galpón rural contradice la gramática; `props.tres` intacto para la ciudad); `bridge_deck` siempre visible, sin sombra, GI estático. Menores: docstrings, «rural» por el dato declarado, fila de pads atada al conteo de POI rurales, `GROVE_JITTER` 0,28, `FRONT_FENCE_OFFSET` hacia adentro, `uniform` del agua explícitos (`CREEK_WATER_PARAMS`), `front: "+X-run"` para piezas de tramo, `PIECE_HEIGHT` con las cuatro alturas nuevas, `dark_blocks` con orden estricto, `_ushr` con `clampi`, constantes unificadas, `walkway.tres` con albedo ≤ 1 ((1; 0,97; 0,90)): **el contraste de valor vereda/calzada queda en 0,97× contra el 1,25× pedido** y es inalcanzable con albedo ≤ 1 porque vereda y calzada muestrean el mismo parche del atlas: la separación la lleva el cordón de 15 cm y el matiz (38° de distancia); recuperar valor pide un parche más claro del atlas o textura propia (pendiente de arte). Resultado: `render_check` HIGH máx **793**, `.tscn` 404,7 KB, 41 casas, 52 destructibles, 91 800 HP, 1 414 árboles, 234 tramos de cerco, 75 props, densidad 7/16/9/7. Abierto: `balance_check` completo (una semilla dio acierto 0,587/0,530/0,537 contra el techo 0,55: la aserción es sobre el promedio de tres) y los troncos naranjas del follaje desde el aire (paleta).

> **Nota de P2c, WP-D2 (2026-09-23, pase de diseño, hechos medidos)**: el JSON (`city/designs/town_a.json`, 482 líneas comentadas) gana `plaza` (`polygon`, `datum`, `props[]`), `markers[]` (`battery|enemy|drone|camera`: reemplazan a los sorteados de su clase; los 4 `battery` declarados ocupan los 4 primeros de los 5 puestos de calle, el quinto y los 3 de azotea siguen sorteados para no romper `Post0..7`), `poi[].block` (`"m06"`, `null` = lote rural con cota del terreno, ausente = donde caiga), `groves[]` (`polygon`, `species` con pesos, `density`, `min_spacing`, `clear{streets, blocks, houses, route}`), `fences[]` (`wire|picket`, `gap_at_streets`), `props[]` (`piece`, `pos`, `yaw_deg`, `on_terrain`, `align_to_slope`), `bridge.piece`; `houses[].tree` y `.fence` ahora se siembran (árbol de patio a 10 m del frente, cerco del frente por tramos). `TownDesign` fusiona el manifiesto de WP-D1 (`manifest()`, `piece_class/scene/front/height()`, `manifest_ready()`; `PIECE_CLASS` queda como fondo; avisos partidos en `warnings` = nombre desconocido y `pending` = pieza que falta). `TownPlan`: `plaza_*`, `bridge_at/span/deck_width/yaw/piece`, arboledas en arrays paralelos (`grove_species/points/yaws/scales/source`: un diccionario por árbol costaba 5× más), `fence_points/yaws/kinds`, `prop_placements`; firma con `plaza=`, `bridge=`, `gr<n>=`, `pr<n>=` (con el dueño del prop, que es lo que distingue «movió su árbol» de «movió un banco de la plaza»). `TownPlanner`: `_place_plaza/_place_groves/_place_fences/_place_props/_place_bridge/_declared_markers`, siembra posicional con `SALT_GROVE/FENCE/PROP`. `CityGrid`: `_build_plaza` (`Floor` + `Lawn` con inset 14 m: con 8 m la plaza se leía como pozo negro con marco claro), `_build_groves` (un `MultiMeshInstance3D` por especie), `_build_fences`, `_build_props` (`MultiMesh` por pieza con ≥ 8 instancias, el resto fundido en `Props/Merged`), `_build_bridge` (`Deck` + `DeckBody` con caja de 12 × 0,8 × 20; **la cinta de la ruta dentro del vano toma `y` de la recta entre los extremos**: `route_height_fn()`), `visibility_range_end` 300 m (follaje y cercos) y 170 m (props). **El pueblo de `docs/17` materializado**: plaza = m09 entera (1 779 m², 21 props), escuela en m08 en (−11,9; −15,8) con la fachada al este alineada con el mástil de la plaza a 42,9 m, estación en m06 frente a la ruta, tanque en m05 en (135, −20) **en medio del lote** (la regla «el frente cae sobre un lado de la manzana» pasa a ser solo de casas), silo y galpón rurales en (−95, 70) y (−74, 76) (`block: null`), `mid_0` movido de m09 a m10 (daba a la plaza su borde construido del este) y `mid_2` al frente de la calle 4 de m03 (dejaba entrar la casa de la puerta abierta); **cruce del arroyo a arco −230 m** (−212,7; −83,8), cruce a 75°, vano a 22 m del acceso oeste del jefe; arboleda del arroyo en dos polígonos partidos por el corredor de ruta y cortados a r 250 (más allá el relieve se apaga), `min_spacing` 5 m. Conteos: casas 46 → 41 (m06 −4, m09 −5, m08 −2 +1, m05 −1, +2 m00, +2 m04, +1 m03 puerta abierta, +1 m11), destructibles 52, **HP 91 800** (41 × 1 300 + 11 × 3 500), 1 414 instancias de follaje (148 `tree_large`, 51 `tree_xl`, 65 `bush_a`, 566 `corn_a`, 584 `corn_b`; la más cercana a la ruta a 21,4 m), 286 tramos de cerco (1 050 m de alambre, 400 m de tabla, 0 sobre calzada), 75 props en 19 piezas, 12 caseríos re-resueltos (≥ 14 m de la franja de calle: el pad aplana 7,2 m y desvanece 6 más). `town_a.tscn` 406,6 KB con 16 `.res` externos (con las 1 414 transformadas en texto se iba a 1 843 KB). **Bug real corregido**: `TownPlan.mix()` implementaba splitmix64 con el `>>` aritmético de GDScript, así que `z ^ (z >> 31)` dejaba el bit 63 en cero y `mix_unit()` nunca pasaba de 0,5 (1 600 llaves, 1 600 en la mitad baja): el sauce de peso 0,5 se llevaba las 288 instancias, la maleza giraba solo medio círculo y los puestos de pila medían 4–5 m y nunca 5–6 → `_ushr()` lógico. **Defecto de WP-D1 mitigado**: `_setup_poi_pads` orienta el pad con `(cos, sin)` y `parcel_footprint` con `(cos, −sin)`: espejados con giro ≠ 0 (4,5 cm de esquina fuera del pad) → `field_shed` con `yaw 0` hasta que D3 corrija `build_terrain`. `render_check` HIGH máx **857** (presupuesto 860: los 143 nuevos son sobre todo los cuatro edificios de POI con sombra en tres vistas, plaza, puente y 6 grupos de decorado); LOW 479. `balance_check --only=1` en banda sin recalibrar (victoria a 152 s, integridad 0,748). §4.4 queda descrito por esta nota y `docs/17`.

> **Nota de P2c, WP-D1 (2026-09-23, vano del puente y pads rurales)**: `build_terrain.gd` abre el **vano del puente** apagando la banda civil de la ruta dentro de `bridge.span` medido sobre el arco (un disco cortaba la banda en lente), con fundido de 2 m: el canal baja 2,12 m bajo la rasante y fuera del vano el corredor se aparta 0,008 m del perfil; la pendiente de la ruta se informa fuera del vano (con el vano daba 51,9 %, que es un arroyo, no una pendiente). **Pads de POI rural** para todo `poi` con `block: null` (huella + 3 m, recortado contra calzada y manzanas, cota del terreno en el centro, talud y fusión de plataformas como los caseríos; `params.poi_pads` en el `.res`): `silo` y `field_shed` comparten una plataforma a −2,716 m, planas a ±0,0 mm. `_load_spec` **falla fuerte** (`quit(1)` sin escribir nada) con diseño ausente, truncado o que no parsea, con línea y mensaje. `terrain_check` pasa a **14 filas**: «los chunks miran al cielo» (115 200 triángulos, 0 al suelo), «el vano del puente» (≥ 1,5 m de caída sobre al menos el ancho del cauce: 2,14 m en 10,3 de 16 m; fuera del vano peralte 0,036 m ≤ 0,05) y «pads rurales planos»; la negativa siembra ocho defectos y 9 de 9 filas apuntadas se ponen en rojo. **Colisión de diseño detectada**: el acceso oeste del jefe (`EnemySpawn0`, a `play_radius + 60 = 200 m` de arco) caía sobre el vano (también a 200 m de arco): decisión del orquestador, el cruce del arroyo pasa a **arco −230 m** y el acceso se queda (lo aplica WP-D2). Procedencia en `assets/town/LICENSE-PENDING.md` (una fila por pack con licencia DESCONOCIDA y una por familia procedural).

> **Nota de P2c, WP-T5 (2026-09-22, cierre corto antes del checkpoint, hechos medidos)**: (1) **El relieve no se veía porque los 115 200 triángulos de los cuatro chunks estaban cosidos al revés** y `cull_back` los descartaba: lo que se veía dentro del cuadrado de ±260 m era el `ground_color` del cielo por el agujero del campo lejano (píxel (35, 47, 60) contra cielo (31, 46, 57)), la «arista recta» era el borde del cuadrado de los chunks y la «lámina celeste» desde la ruta era ese mismo agujero contra el horizonte. Ablaciones que lo descartaron todo lo demás: normales sanas (0 en +Y exacto, 0 nulas, inclinación máxima 35,5°), `COLOR` presente y nunca nulo, `asphalt.res` como control con 40 340/40 340 triángulos hacia arriba, rugosidad 0,99 / especular 0,08 sin brillo rasante; SDFGI y `build_environment.gd` intactos. Arreglo en `_build_chunk` (`build_terrain.gd`): giro de los índices conservando la alternancia de diagonal; regla: cara al cielo ⇒ `(v1−v0)×(v2−v0)·UP` negativo (la misma que `CityGrid._field_quad`). **Ningún check miraba el giro de los chunks** (fila pendiente para D4). (2) Paleta del `terrain.gdshader`: los tres tonos que no eran pasto estaban por debajo del pasto y leían al revés (pendiente pelada = mancha oscura, lecho = pozo negro, patio = agujero): tierra (0,196; 0,152; 0,104), roca (0,186; 0,184; 0,176), arena de lecho (0,285; 0,252; 0,182), pasto igual (tono medio de `field.tres`); el aporte de tierra de la máscara urbana pasa de 0,8 a `CIVIL_DIRT` 0,33 (el patio iluminado sale (111, 97, 80) contra (85, 70, 58) del campo). (3) **La muesca periódica del borde de las veredas era la cinta de asfalto, no la vereda**: el atlas `t_roads_diffuse.png` trae en las columnas 981–1007 el cordón pintado de la pieza, y `ribbon` estiraba el tile entero a lo ancho de cada calle, así que esa franja caía al 75–94 % de la calzada y aparecía y desaparecía con la mipmap en cada junta de celda de 10 m (escalera de saltos de 5–6 px cada 1,25 m); la geometría de la vereda estaba limpia (offsets exactos 0,00 y 3,00 m). Arreglo: `ROAD_SMOOTH_UV` (tile recortado a la zona lisa), `ribbon(uv_rect)`, **la ruta conserva `ROAD_UV` con marcas y calles y pasajes van lisos** (gramática de `docs/17` §4); la vereda pasa a UV continua por longitud acumulada con `SMOOTH_INSET` 0,2 y tajada `CURB_UV_BAND` 0,12 para el cordón (vértices de `walkways.res` 13 744 → 10 778). (4) **Off-by-one de cabos** en `terrain_check._corridor_distance()` y `build_terrain._street_corridor()` (`street_stub_of(index + 1, …)`: el grafo indexa 0 = ruta, `k+1` = `streets[k]`): la holgura del arroyo pasa de 6,57 a **9,69 m** contra la calle 1, que más los 12 m de banco da los ~22 m del cálculo a mano de WP-T3 (las dos cuentas eran correctas y medían cosas distintas). (5) Tres caseríos movidos en el JSON con comentario (`Decor_House_00` 34,0 m, `_04` 30,4 m, `_05` 16,3 m; búsqueda conjunta por mínimos cuadrados sobre rejilla de 0,5 m con ≥ 20 m del eje del arroyo, ≥ 16 m del eje de la ruta, ≥ 6 m de manzanas, ≥ 14 m entre vecinas): la regla «≥ 1 m fuera de la franja de calle» no alcanza porque el pad de un caserío aplana un disco de ~7,2 m de radio (con 1,04 m `city_check` cazó asfalto a −1,5 cm del terreno) → **≥ 8,5 m**; quedan nits preexistentes para la tanda 2 (`01`↔`03` a 13,2 m, `03` a 17,6 m del arroyo, `11` a 13,5 m de la ruta, `06`/`07` a ~1 m de la franja de c7). (6) `build_terrain._load_spec` leía el JSON crudo y con el primer comentario `//` habría caído al spec de reserva **sin fallar**: ahora usa `_strip_comments` de `TownDesign`; sigue pendiente hacerlo fallar fuerte si el JSON no parsea. (7) Solape coplanar latente de 4 m entre el borde de los chunks (±260) y el agujero del anillo lejano (±256): hoy invisible (ambos a `y = 0` exacto con el mismo material), a cerrar en D3/D4. `render_check` 713; `town_a.tscn` 309,8 KB; `city_check`, `terrain_check` (+ negativa), `town_plan_check`, `gait_check`, `round_check` en verde.

> **Nota de P2c, WP-T4 (2026-09-22, integración, hechos medidos)**: el terreno entra al nivel: `CityGrid._build_ground()` monta `Ground` con el `HeightMapShape3D` 513² **en el origen y sin escalar**, cuatro cajas de anillo a `y = 0` de ±256 a ±600 m, una caja de seguridad con la cara superior en −6 m (mínimo del relieve −5,53) y los cuatro chunks en el origen; el `PlaneMesh` de 1 200 m a `y = 0` se retira porque asomaría donde el relieve baja de cero (el arroyo, las vaguadas) y lo reemplaza un **anillo cuadrado con agujero de 260 a 600 m** (`SurfaceTool`, 720 tris, mismo `terrain.tres` con COLOR «todo pasto»); el agujero coincide con el borde de los chunks (260) y no con el radio de desvanecido (256) para que la junta sea plana de los dos lados (medida: 1,5 mm). `TownPlanner.generate()` carga `assets/city/terrain/town_a_terrain.res` si existe y resuelve con él (`block_datum` del baricentro; `_place_hamlets` pone los caseríos a la altura del terreno), y `build_terrain.gd` llama a `generate()` sin leer `block_datum`, así que la vuelta no se muerde la cola (md5 estable). Cotas por `on_terrain()` para caseríos, rocas (−20 cm), props (con `normal_at`), apariciones, puestos, dron, cámara y centro; `yaw_jitter` aplicado al edificio en `_facade_yaw()`. **Ruta exterior**: las baldosas planas de 10 m inclinadas por sus extremos daban −0,015…+0,085 m de separación (se entierran y flotan) porque en el anillo de desvanecido 230–256 m el perfil se apaga contra el plano y el terreno llega al 5,44 %; baldosas de 5 m seguían bajo el piso de 1 cm y las de 4 m entraban a costa de 182 instancias → **la cinta cubre los 1 127 m de ruta y `RoadRoute` desaparece** (separación 0,023–0,043 m). Tres defectos de subdivisión que solo existen con relieve, corregidos en `road_mesh.gd`: `polygon_mesh()` hacía un abanico de un triángulo por lado (calzada 30 cm enterrada en un borde de un cruce de 14 m) → filas; la cinta no se subdividía a lo ancho (9 m con peralte dejaban la cuerda 2 cm bajo el terreno) → `MAX_STEP_ACROSS` 2,5 m; `MAX_STEP` 2,5 → 1,25 m (una cuerda de 2,5 m se hundía 4 cm donde la máscara quiebra a 0,07 m/m). Coste: asfalto 2 042 → **40 340 tris** (`asphalt.res` 529 KB, un lote), veredas 6 872 (122 KB). **Pads de caserío** en `build_terrain.gd`: rectángulo (huella + margen) y no disco (tres casas están a 8,2–9,5 m del eje de su calle y el disco aplanaba la calzada: pendiente bajo eje 21,6 %), margen recortado contra calzada y manzanas con piso de 1 m, talud por pad acotado por la geometría, y dos casas cuyo escalón no cabe entre ellas comparten terraza con cota minimax ponderada (12 pads en 5 plataformas, 12 huellas planas a ±0,0 mm). `town_a.tscn` **309,8 KB** (P2b 356 con las mallas adentro). `render_check` HIGH máx **714** (P2b 712; presupuesto 860): viario −4, chunks +4, campo +1, plano viejo −1. `perf_report boss_and_city`: `physics_ms_avg` 1,87–2,12 (mediana 1,90) contra 1,903 de la referencia → plano; fase instrumentada 0,534–0,539 ms contra 0,542: el heightfield no costó nada. **Corrección al plan**: el tope «`physics_tick_ms` ≤ 1,40» del criterio 11 no corresponde a ninguna métrica de `2026-09-20-p2.json` (que da 1,903 para `boss_and_city`): el criterio pasa a «sin regresión contra la referencia (±10 %)». `perf_report` escribió `docs/perf/2026-09-22.json`. Pendientes de diseño al cierre: `Decor_House_04/05` dentro del arroyo y `_00` sobre la banquina (se corrigen en WP-T5); el arroyo desaparece bajo la ruta porque la máscara civil del corredor lo borra: el vano del puente lo abre WP-D1 (terreno que baja en el vano y tablero con el perfil de la ruta); `poi`, `groves`, `fences`, `props`, `plaza`, `bridge` declarados y sin sembrar (D1/D2).

> **Nota de P2c, tanda 1 (2026-09-22, WP-T1/T2/T3, hechos medidos)**: el pueblo deja de sortearse y pasa a **diseñarse a mano**: `city/designs/town_a.json` (admite comentarios `//`; 23 nodos, 10 calles que pasan de largo por sus nodos intermedios, 14 cabos de 7,8–16,8 m todos con tranquera `gate`, 12 manzanas por sus nodos, 46 casas con `front`/`t`/pieza/variante/color/estado, 7 POI, 12 caseríos, 6 rocas, `creek`/`bridge`/`terrain`) cargado y validado por `city/town_design.gd` (`TownDesign.load_json`, errores con `archivo:línea`, ids únicos, ruta sobre sus nodos en orden ±0,25 m, cabo ⇒ cierre, manzanas convexas, `t ∈ [0,1]`, pieza desconocida = aviso y omisión; `design_hash()` sobre el JSON normalizado) y resuelto por `TownPlanner.resolve(design, terrain)`; `generate(seed)` conserva la firma pero **ignora sus argumentos** (una fila de `town_plan_check` lo verifica). Se retiraron `_trace_route`, `_trace_streets`, `_clip_to_circle`, `BLOCK_COUNT_MIN` y el tallado con rectas infinitas. **`block_radius` pasa de 150 a 180 m** (ya no se recorta nada: los vértices de manzana llegan a r 165,7 m y los nodos extremos de la ruta a 159 m de arco). La mezcla posicional se siembra con `variation_seed` (20260922), **no** con el hash del diseño: recolorear una casa cambia una sola línea de la firma y no baraja a las otras 45. El giro fino viaja en `yaw_jitter` de la parcela y lo aplica el constructor al edificio (el lote se mide derecho: los lotes se tocan borde con borde). Nombres posicionales `Building_House_<manzana>_<sitio>`. El andamio reproduce el pueblo de P2b con desvío máximo de 0,72 mm; las transversales 1 y 7 se extienden a su nodo y las dos paralelas colgantes cierran en T; cuatro casas de caserío que en P2b estaban **sobre la calzada** (nadie lo medía) se corrieron 1,3–35,7 m. **Grafo en `TownPlan`** (`nodes`, `street_nodes`, `street_stubs`, `street_kind`, `street_closures`, `block_datum`, `block_rings`, `design_hash`; `node_at` rellena `poly` y respeta el `radius` guardado; `graph_problems()` con seis reglas: punta en nodo o cabo con cierre, ≥ 35° entre bocas (el diseño da 74,5°), polígono de nodo convexo con las medias franjas, **ningún nodo se come un quiebre de su calle**, ningún cruce sin nodo, anillos dentro de su manzana; `refresh_nodes()` solo para planos a mano). **Viario de cintas** (`city/road_mesh.gd`, `RoadMesh` estático sin nodos ni RNG): `ribbon` con miter en los quiebres y corte exacto a `radius` metros del nodo (ni hueco ni solape: es lo que garantiza cero coplanares), `node_polygon` = intersección de semiplanos con **un radio por nodo** (la esquina verdadera más lejana + chaflán 0,8 m; con un radio por calle el polígono salía cóncavo), `ring` de vereda con cordón de 0,15 m y ancho por lado, `closure` (tranquera 60 tris, alcantarilla 36, alambrado 72), `clip_ribbon_at_nodes` devuelve una polilínea por tramo (la ruta cruza siete transversales). Atlas `Road_Chunk_5`: la cara superior es un solo cuadrilátero de 10 × 10 m en `Rect2(0,8563, 0,1508, 0,1353, 0,1353)` y el eje longitudinal cae sobre la **V**; el atlas no es repetible y nada de `fposmod` sobre la posición del mundo en las UV (daba moiré). `CityGrid._build_streets` → `Streets/Asphalt` + `Streets/Walkways` (dos `MeshInstance3D` sin sombra, `.res` por `save_street_meshes`) + `Streets/RoadRoute` (baldosas más allá de `block_radius + 20`); desaparecen `Crossings`, `Sidewalks`, `BlockPads`, `_lay_offset`, `_build_crossing_mesh`. Sobre el plano resuelto: 21 cruces con polígono, 430 tris de asfalto y 1 032 de vereda (sin terreno no se subdivide), **0 muestras sin asfalto, 0 coplanares, cordón 0,15 ± 0,01, toda punta en su nodo**. **Terreno** (`city/town_terrain.gd`, `TownTerrain`: rejilla 513² a 1 m desde (−256, −256), `height_at` bilineal, `normal_at`, `slope_at`, `place`, `build_shape`, firma a mm; `tools/build_terrain.gd` lee el JSON, `h = lerp(h_noise, h_datum, mask)` con lomas 120 m ±3,5, grano 25 m ±0,6, canal del arroyo 6 m × 2,4 m con bancos de 9 m, cota constante por manzana, perfil de ruta con gradiente máximo 1,85 %, máscara por **unión probabilística** `1 − Π(1 − bᵢ)` porque el `max()` dejaba una arruga recta de 0,22 m/m en el borde del pueblo; desvanecido `[230, 256]`; determinista byte a byte): alturas −5,5…3,6 m, pendiente bajo ejes 5,44 % (tope 8), manzanas 0,000 %, `HeightMapShape3D` 513² cuadrado sin escalar (error rejilla ↔ forma 0,00000 m), 4 chunks de 28 800 tris con bordes compartidos, **el heightfield no cuesta nada medible** frente a la caja (0,686 vs 0,687 ms/tick, A/B alternado), 4/2/1 lotes por vista. El arroyo del andamio invadía tres cabos del noroeste: se rehízo con cruce a 75°, banda r 200–222 m (293 m), holgura mínima 6,57 m a corredores con cabo y 16,6 m de eje a eje con la ruta (el tope geométrico es 17 m por la exención de `span/2 + bank`). Pendiente para el checkpoint: sobre relieve la planta del pie del jefe **pivota** hasta 0,43 m alrededor del tobillo (el IK apunta al tobillo; `enemies/locomotion/leg.gd`), con guarda de regresión en 0,50 m en `gait_check`. Integración (terreno en el nivel, cotas, re-horneado, filas estrictas) en WP-T4; §4, §7 y §11.2 quedan corregidos por esta nota y `docs/17` describe el diseño.

> **Nota del cierre de la revisión de P2b (2026-09-22)**: revisión de código (`godot-code-reviewer`, solo lectura) con 1 bloqueante, 7 importantes y ~30 menores, todos corregidos. **Bloqueante**: nada verificaba que `town_a.tscn` estuviera al día con el planificador; `city_check` ahora exige `plan.signature() == TownPlanner.generate(TownPlanner.TOWN_SEED).signature()` (semilla única; `build_town.gd` la lee en ejecución porque un `const` que nombre a `TownPlanner` compila `TownPlan` antes de los autoload). La fila cazó un bug real al primer intento: el **cero negativo** (`-normal` con `y == 0` daba `-0.000` en la firma y el `.tscn` lo releía como `+0`): `TownPlan._zero()` lo normaliza. El determinismo dejó de apoyarse en `String.hash()` (detalle del motor): mezclador **splitmix64** propio (`TownPlan.mix/mix_all/mix_unit`); el pueblo regenerado cambió a **46 casas, 53 destructibles, 84 300 HP** (12 manzanas, 4 a oscuras, ~134 700 tris), caseríos a 157–212 m (el arco se convierte a radio por bisección); `INSIDE_MARGIN` 3 → 0,5 m con prueba de las **cuatro esquinas** (`TownPlan.parcel_inside`) y `_place_big()` que prueba hasta ocho lados (antes el hito podía quedar fuera en silencio); las casas de costado de `_lay_big` cuentan contra el cupo; el respaldo de rocas relaja el cono de a un grado (la más metida a 50,1°); `street_axis(-1)` y afines devuelven vacío; `signature()` cubre cámara, veredas, `block_streets`, puestos de azotea y `base_y/hp/destructible/street`; comentario del dron corregido (mismo lado que la aparición 1). El recorte por distancia de la decoración **se borró** (no se serializaba y ahorraba 0 lotes). `city_check`: fachada contra la **escena** (`building.position` vs `parcel_position()`, peor desvío 0,000 m), marcadores posición a posición contra el plano (`MARKER_TOLERANCE` 0,05; puestos de azotea con `POST_ROOF_CLEARANCE` y coherencia ≤ 3 m), constantes derivadas del plano, guardas de `null`, `_sample_budgets()` con caché; `town_plan_check`: `_parcel_problems()` compartido por las cinco negativas, solapes también entre decorativas (cazó `Decor_House_03` sobre `_01`: la profundidad de las parcelas de caserío era la distancia a la banquina; ahora la huella es la casa), `_frontage_matches_street()`. `_bake_piece_mesh()` avisa si la pieza trae varias mallas/superficies o está anidada; `_damage_materials`/`_dark_materials` se purgan al salir el último edificio. **`play_centre()` devuelve coordenadas locales del distrito** (contrato corregido): los showcases usan `to_global()`. `render_check` **712** lotes (HIGH y B), LOW 416. Otros: `city_centre()` del jefe saltea ruinas y elige el más cercano (`round_check` 17 derriba la escuela de verdad); `FakeTown` con 9 manzanas y 4 tramos (distinto del pueblo a propósito); `round_check` 16 con piso de 50 edificios; `_city_focus()` con `to_global()`. **Balance**: `balance_check` estaba calibrado contra 92 100 HP; se remide en la suite y se recalibra si hace falta.

> **Nota del cierre de P2b (2026-09-22)**: `render_check` en verde a **772 lotes** (HIGH y variante B; LOW 431) desde 994/998. Perfilado por grupo desde una pose aérea: `Buildings` 95 lotes, `Decor` 12, `Streets` 5, suelo 1 = 113 por viewport; **83 de los 88 lotes de edificios eran las sombras de las 52 casas** entrando en cada cascada del sol. Fundir casas de caserío y rocas en MultiMesh **costó 4 lotes más** (el AABB fundido nunca se descarta y entra en todas las cascadas; revertido) y el recorte por distancia ahorra 0 (el pueblo mide 300 m). Solución: casas de 2,2–5,5 m y decoración **sin sombra propia** (`cast_shadow` aplicado en `CityGrid._ready()`: una anulación sobre un nodo de una pieza instanciada no se serializa y forzar el dueño copia la malla por casa); los 7 grandes siguen proyectando; las casas reciben sombra y oclusión de SDFGI/SSAO. Las casas de caserío pasan a capa **WORLD** (frenan al dron y al rayo del arma, no son ciudad), también aplicada en `_ready()` (el serializador omite el valor por defecto de la clase y ganaba el 128 de la pieza; lo cazó `city_check`). Legibilidad: `assets/city/materials/walkway.tres` (copia de `roads.tres` con `albedo_color` (1,34, 1,27, 1,14), sin VRAM extra) en `Sidewalks` y `BlockPads`; `field.tres` con ruido de 83 m en 5 octavas y rampa de dos tonos tierra/pasto; caseríos a **165–211 m** (el sorteo crece solo hacia afuera); luminancias medidas en la cenital: campo 0,215–0,229, calzada 0,363 afuera y 0,529 en el pueblo. `town_plan_check` asevera decorativas en 150–220 m; `city_check` `decoración` exige capa WORLD y no CITY. Palanca pendiente para devolverles la sombra a las casas cercanas: `directional_shadow_max_distance` en `sun_dusk.tres`/preset. Nota de medición: con el editor de Godot abierto el `draw calls máx` (pico de un cuadro) sube a 944–1 016 en corridas cargadas aunque la media no se mueva.

> **Nota de P2b, WP-D (2026-09-21)**: `tools/city_check.gd` reescrito contra el **plano** (`TownPlan`), 26 filas (§11.2 queda obsoleto): conteos por rol 52/5/1/1 = 59, HP 92 100 en banda [87 000, 97 000], círculo (59 dentro, el más lejano a 136,7 m; 12 casas de caserío y 6 rocas afuera, la más cercana a 171,8 m; ningún nodo de `Decor` con `building.gd` ni en el grupo `buildings`; la maleza sí puede caer dentro), fachada por la misma fórmula que `TownPlan.parcel_position()` (desvío 0,000 m, base 0,0000, giro 0,0000°), ruta muestreada cada 2 m (564 muestras, calzada de 10,0 m debajo de todas, banquina en las 147 del pueblo, 560/557 m a cada lado; se pregunta si alguna pieza **cubre** el punto, no cuál es la más cercana), 5 MultiMesh con 1 013 instancias y 0 colisionadores, marcas viales a lo largo de la ruta **y** de las 9 calles, campo `field.tres` ≠ asfalto, 6 rocas a ≥ 211 m y ≥ 48,6° del eje del dron, 0 oclusores, 4 de 12 manzanas a oscuras con 4 materiales, hito de 18,1 m en banda [17, 20], 2 mallas de escombro, marcadores (4 accesos a 200 m, 8 puestos, `DroneSpawn`, `TownCentre`, `CameraFixedPose`), presupuesto estimado 148 lotes (la medida real es de `render_check`), `decor_inert` (200 × 6 HP a `Decor_House_00`: 0 destrucciones, integridad 1,0), `collapse_time` 4,93 s, `protected` ×3,00 con la manzana de la escuela a oscuras (semilla 2), `debris_cap` 24 con casa/grande intercalados, prueba negativa `negative_play_circle`. `tools/build_district.gd` y `district_a.tscn` **borrados**; `city_showcase` sobre el pueblo; `town_plan_check` y `town_import_check` en los runners. **`render_check` en rojo**: 994/998 lotes contra 900 (fps 129/152 sobran): el pueblo cuesta 48 lotes por viewport contra 17 del distrito, ×3 viewports de FAST_WIDE; cierre en curso (casas decorativas y rocas a MultiMesh conservando colisión, fusión de MultiMesh de props). Pendientes de arte anotados: calzada distinguible de veredas y pads solo por las marcas (mismo `roads.tres`), campo como masa negra al anochecer y caseríos invisibles a 172–347 m (cierre en curso: material derivado más claro para veredas/pads, `field.tres` +20–30 % con variación de tono, caseríos a 150–220 m). §7: distinguir «lotes de la escena» (148) de «lotes por cuadro» (994 con tres viewports).

> **Nota de P2b «Pueblo de ruta» (2026-09-21, WP-A/B/C)**: el distrito rectangular (`district_a.tscn`, `build_district.gd`, modelo de carriles) queda **reemplazado** por un pueblo de ruta: `city/town_plan.gd` (`TownPlan extends Resource`: ruta como polilínea, ejes de calle, manzanas como polígonos convexos, parcelas con `frontage_point`/`frontage_normal`, círculo `play_centre`/`play_radius` 140 m, roles `HOUSE/MEDIUM/LANDMARK/SCHOOL/DECOR`, marcadores), `city/town_planner.gd` (`TownPlanner.generate(seed, radius, field)`, determinista por semilla y sin assets), `city/city_grid.gd` **reescrito conservando `class_name CityGrid`** (constructor del plano: conserva `_spawn_building`, el horneado de MultiMesh y el racionado de ventanas; retira carriles, celdas, oclusores: `occluder_for()` devuelve `null`), `tools/build_town.gd` (`godot --headless -s`, semilla 0 → `city/districts/town_a.tscn`), `tools/town_plan_check` (2,5 s, sin assets). §4, §4.1, §4.3, §4.4, §7 y la nota de WP-24b de esta sección quedan **obsoletos de raíz**: manda esta nota. Pueblo (semilla 0): ruta de 1 127 m con 4 vértices y quiebres de 12–22° **fuera** del disco de manzanas (dentro del pueblo la ruta es recta: manzanas talladas con semiplanos), a 31,3 m del centro; 9 calles (7 transversales con separación 48–56 m y ángulo 74–106°, que van de una paralela de fondo a la otra más un cabo de 7–17 m; 2 paralelas a +52 y −61 m, no simétricas); 12 manzanas convexas de 877–1 953 m², 4 a oscuras (30 %); **52 casas** (`Building_House_NN`, perfil `house.tres`: 1 300 HP, `value 60`, escombro compartido, `damage_shader` de paleta) + 5 medianos (`Building_Mid_0..4`: `BuildingBlock_18` ×2, `_19` ×2, `_24`) + hito `Building_Landmark` (`tower_b` ×1,45 = 18,1 m) + **`Building_School`** (`tower_b` ×1,15 = 14,4 m, sobre la ruta, la parcela más cercana al centro) = **59 destructibles, 92 100 HP**; afuera, 12 `Decor_House_NN` en dos caseríos a 172–347 m instanciadas **sin `building.gd`** (indestructibles: no entran al grupo `buildings` ni a `CityIntegrity`), 6 rocas a 193–256 m fuera del cono del dron, 96 props (maleza, basura, barril) en 4 MultiMesh; calles en **5 MultiMesh** sin colisión (`RoadRoute` 113, `RoadStreets` 152, `Crossings` 68, `Sidewalks` 368, `BlockPads` 312 = 1 013 instancias; los pads pavimentan solo la franja de 9 m desde la línea municipal), suelo `field.tres` (campo, no asfalto); ~145 000 triángulos, ~148 lotes, 8 materiales; bases a `y = 0,18`; sin cuerpos escalados; sin `Building_3` (el jefe de 29 m domina la silueta). Fachadas: las FBX de VoxelCity miran a −Z y las GLB del pueblo a −X (`_facade_yaw()` por `town_kind`); `Building.apply_variation_yaw()` da yaw libre. Marcas viales a lo largo de la ruta con `yaw = atan2(−d.z, d.x)`. Props de azotea solo en los 7 grandes. Marcadores en el distrito: `Spawns/EnemySpawn0..3` a `play_radius + 60` (0 y 1 sobre la ruta), `BatteryPosts/Post0..7` (5 en cruces, 3 en azoteas), `DroneSpawn` (sobre la ruta a 120 m, mirando al pueblo), `TownCentre` (grupo persistente `town_centre`), `CameraFixedPose`; el nivel los adopta (`docs/11`). Piezas del pack **nuke Free Sample** remalladas (`docs/05`). Pendiente de pulido observado en las capturas: la calzada se confunde con veredas y pads (mismo atlas `roads.tres`) y el campo es muy plano; `tower.tres` no lleva `damage_shader` (sus texturas no son paleta: no hace falta).

> **Nota del cierre de la revisión (2026-09-20)**: `Building` lleva `_pool_reserved` (plazas reservadas de verdad en el `VFXPool`) aparte de `_active_emitters`; el camino sin pool no reserva ni devuelve; los estáticos se resetean cuando sale del árbol el último edificio del grupo y el pool cacheado se descarta si murió o salió del árbol.

> **Nota de WP-26 (2026-09-20)**: el presupuesto de emisores se unifica: `Building.MAX_EMITTERS` (12) queda como respaldo sin pool y el `DustBurst` por edificio pide su plaza con `VFXPool.reserve_emitters()`; la columna `Smoke` por edificio se apaga cuando hay pool y la reemplaza `collapse` (120 partículas + `FogVolume` de 18 m con densidad 0,05; 2 emisores, pool 2) disparado por `building_destroyed`. El crujido al pasar a DAMAGED (`damage_crack`, WP-27) suena por `stage_changed`.

> **Nota de WP-25b (2026-09-20)**: la integridad pasa a `ratio = Σ wᵢ·hpᵢ / Σ wᵢ·hp_inicialᵢ` con `w = protected_weight` (3,0) para el edificio protegido (`CityIntegrity.set_protected()`, señal `protected_fallen` una sola vez). **Ventanas racionadas**: `CityGrid.dark_blocks()` sortea con `Global.round_seed` un conjunto de **tamaño fijo** `round(manzanas × 0,30)` = 5 de 15 (una Bernoulli por manzana sacaba el recuento fuera de 25–35 % una de cada tres partidas); `Building` apaga la emisión de sus ventanas con una copia de material **por familia** (`buildings_001/002`), nunca el `.tres` compartido, sin lotes de dibujo extra; el protegido siempre encendido. `city_check` suma los sub-checks `ventanas` y `protegido`.

> **Nota de WP-24e (2026-09-20)**: los 15 `OccluderInstance3D` por manzana (§7) nunca se retiraban al derrumbe y, con la oclusión encendida en las `SubViewport` del ojo de pez, dejaban losas fantasma de hasta 75 m que culeaban el cuadro entero cuando el dron entraba en la huella de un edificio caído o tapaban al coloso (el «mapa y enemigo que aparecen y desaparecen» del usuario). Ahora `CityGrid.occluder_for(building)` (solo para el edificio más alto de la manzana, resuelto por nombre y metadato `cell`, sin regenerar `district_a.tscn`) y `Building._finish_collapse()` lo oculta (`reset()` lo devuelve); `city_check` 8b lo verifica. Además la oclusión queda **apagada** en el proyecto y en todos los presets (`docs/13` §3.4).

> **Nota de WP-24 (2026-09-20)**: los materiales de ciudad `assets/city/materials/{buildings_001,buildings_002,props,roads}.tres` pasan a **`emission_operator = MULTIPLY`**: con el ADD de fábrica y `emission = blanco`, toda la fachada emitía 1 000 nits y el bake de ventanas no se veía (era la «planitud» de la ciudad). Regla para cualquier material nuevo que use `emission_texture` como **máscara**: `emission_operator = MULTIPLY`. `gi_mode` verificado por `city_check._check_gi_modes()` (STATIC en lo estático, DISABLED en ruinas, humo, polvo y partículas).

> **Nota de WP-24b (2026-09-20)**: el distrito A se regeneró con una **rejilla no uniforme por carriles** (`CityGrid.lane_count/lane_kind/lane_width/lane_start/lane_centre`, `street_width_at`, `get_core_extent`, `avenue_crossing`): carriles de edificio de 32 m, **calles de 16 m** (vereda 3 + calzada 10 + vereda 3) y **una avenida por eje de 32 m** (vereda 5 + calzada 10 + cantero 2 + calzada 10 + vereda 5), con anillo perimetral de 16 m → **432 × 272 m** (núcleo 400 × 240; antes 480 × 288 con cada calle ocupando una celda entera de asfalto). Calzada a 0,03 m y vereda/cantero/patio a 0,18 m (cordón de 15 cm = cara lateral de `Sidewalk_Chunk_2`, que es una losa plana sin cordón modelado); base de edificio a 0,18 m (antes hundidos 18 cm). Cinco `MultiMeshInstance3D` (`RoadEW` 150, `RoadNS` 126 girada 90° para que las bandas pintadas corran a lo largo, `Crossings` 140 con una malla propia de asfalto liso que apunta a un parche del atlas `roads.tres`, `Sidewalks` 768, `BlockPads` 240 de `Sidewalk_Tile_1` a escala uniforme 0,8), 1 424 instancias, 0 colisionadores de calle; sin senda peatonal (el atlas no la trae). **Fachadas a la línea municipal**: cada manzana sortea molinete o peine, el lado largo del edificio da a la calle y el resto es patio (`city_check._check_facade`: ≤ 0,05 m de la línea, base 0,18 ± 0,011). **Silueta**: 6 hitos `Building_3` a `height_scale` 0,90–1,00 (74–80 m, pisos reales) elegidos entre las celdas de perfil torre por cercanía al cruce de avenidas con separación ≥ 72 m; 15 torres medias `tower_b`/`block_mid` a 1,20–1,35 (15–17 m); 39 bloques bajos a 0,85–1,20 (7–15 m). Se descartó la opción «`Building_3` a 0,4–0,6» de la Nota de WP-13: dejaba pisos de 1,2–1,7 m, que es lo que el usuario vio como «estructuras muy escaladas». **Props a escala** (`nodes/root_scale` por pieza, tabla en `city_import_check.ROOT_SCALE_BY_PIECE` ± 0,01): `SateliteDish` 2,0 (1,8 m), `Advertising_6` 2,8 (3,4 × 5,0 m, vertical), `Advertising_7` 3,3 (5,9 × 3,0 m, horizontal), `Advertising_5` 3,0 (2,1 × 4,8 m, importado y fuera de `prop_pieces`: colgarlo de fachada pide otro anclaje); giro en pasos de 90°, huella entera sobre la azotea, altura horneada. **Rocas** 8–18 m, fuera de la extensión y a ≥ 30° de la línea aparición→centro (`rock_spots()`). `EnemySpawn0..3` a (0, ±176) y (±256, 0); marcadores de pila repartidos por todo el distrito (seis en calle, dos en azoteas a techo + 3,2 m porque `BatterySpawner._is_clear()` usa una esfera de 2,5 m) — concentrarlos cerca del centro bajaba la duración media de `balance_check` de 428 a 296 s. `city_check` ganó `grid_layout` por carriles, `_check_facade`, `_check_skyline`, `street_batching` con orientación de bandas y material del cruce, `rocks_ground` 8–18 m y ángulo, `_check_prop_scale`; `MultiMesh.buffer` se decodifica a mano porque `get_instance_transform()` es nula en headless. Efecto en el balance: el jefe hace un 22 % más de `approach` entre blancos (fachadas alineadas) y la partida de control tarda 444–470 s en tirar la ciudad (antes 430–442): el techo de 450 s de `RANGE_CONTROL` queda sin margen (WP-24d lo resuelve con la marcha o ensanchando a 480). §4.1/§4.3/§4.4/§9.3/§10/§11.2 de este documento quedan desactualizados: manda esta nota.

> **Nota de WP-13 (2026-09-19, hechos medidos al importar el pack)**: (1) los FBX NO están en centímetros: ufbx ya convierte unidades y `BuildingBlock_1` importa con 2,50 m de alto a escala 1, así que el `nodes/root_scale` correcto es **5.0** (queda en 12,50 m), no 0.01; todas las menciones a 0.01 en este doc quedan superadas. (2) Los FBX viven en `assets/city/models/` (no `pieces_src/`), las texturas redimensionadas en `assets/city/textures/` y los materiales propios en `assets/city/materials/` (`materials/extract` no sirve: el pack trae rutas absolutas rotas y tres emisivas apuntan a archivos que no existen). (3) El importador no genera LODs para estas mallas voxel (normales duras y atlas por cara: meshoptimizer no encuentra aristas colapsables); el check verifica la opción del preset y el `shadow_mesh`, no niveles de LOD reales. (4) Alturas reales: `Building_3` = **81 m** (única pieza alta; a escala 1 es un rascacielos que empequeñece al coloso de 29 m: WP-20 debe usarla con `height_scale` ≈ 0.4–0.6 o reservarla como hito único), `BuildingBlock_19/18/1/2` = 12,5 m, `BuildingBlock_24` = 8 m; anchos de `BuildingBlock_1/2` = **30 m** (desbordan la celda de 24 m: WP-20 usa el metadato `base_size` de cada pieza y ajusta la celda o escala en XZ). Ver `assets/city/README.md` y `tools/city_import_check.gd`.


Especifica la ciudad que el jugador debe defender: cómo se importa el pack **FreeSample**, cómo se arma el distrito, cómo se destruyen los edificios por etapas, cómo se mide la integridad y cómo se gestionan los escombros. Gobierna dos paquetes de trabajo:

- **WP-13** (§2): import de las 13 piezas FBX, escala, texturas, colisión y LODs. Puede ejecutarse en paralelo con WP-02…11.
- **WP-20** (§3–§8): `Building`, `BuildingProfile`, `CityGrid`, `district_a`, `CityIntegrity`, `DebrisPool`, `RubbleField`, rocas y terreno.

**NO incluye**: cómo el jefe elige objetivo ni los valores de sus ataques (`docs/06`, `docs/07`); el daño de un escombro al dron (`docs/09`); barra de integridad y marcadores (`docs/12`); `Environment`, SDFGI y presets gráficos (`docs/13`); la derrota dentro de la máquina de ronda (`docs/11`).

---

## 2. Import del pack FreeSample (WP-13)

Origen: `godot/assets/_raw/FreeSample.zip` (57 MB, 13 FBX + 12 PNG). El ZIP **no se extrae dentro del repo**: se copia a `godot/assets/city/` sólo lo que se usa, y `godot/assets/_raw/` lleva `.gdignore`.

### 2.1 Inventario de las 13 piezas y uso propuesto

| FBX | Escena de pieza | Rol | Perfil | HP |
|---|---|---|---|---|
| `Building_3` | `city/pieces/tower_a.tscn` | Torre alta, silueta principal del centro | `tower_a` | 3 500 |
| `BuildingBlock_19` | `city/pieces/tower_b.tscn` | Torre alta, variante | `tower_b` | 3 500 |
| `BuildingBlock_18` | `city/pieces/block_mid.tscn` | Bloque medio | `block_mid` | 1 200 |
| `BuildingBlock_1` | `city/pieces/block_low_a.tscn` | Bloque bajo — **pieza de calibración de escala** | `block_low` | 1 200 |
| `BuildingBlock_2` | `city/pieces/block_low_b.tscn` | Bloque bajo, variante | `block_low` | 1 200 |
| `BuildingBlock_24` | `city/pieces/block_low_c.tscn` | Bloque bajo, variante | `block_low` | 1 200 |
| `Advertising_5` | `city/pieces/props/sign_a.tscn` | Cartel de fachada (emisivo) | — | — |
| `Advertising_6` | `city/pieces/props/sign_b.tscn` | Cartel **vertical** de azotea (6 × 9 × 1,5 m con el import a ×5; medido en el diagnóstico de P2, 2026-09-20: los roles de `_6`/`_7` estaban invertidos en esta tabla) | — | — |
| `Advertising_7` | `city/pieces/props/sign_c.tscn` | Cartel **horizontal** de azotea (9 × 4,5 × 2,5 m con el import a ×5) | — | — |
| `SateliteDish` | `city/pieces/props/dish.tscn` | Prop de azotea, se desprende como escombro cosmético | — | — |
| `Road_Chunk_5` | `city/pieces/road_chunk.tscn` | Calzada (instanciada en `MultiMesh`) | — | — |
| `Sidewalk_Chunk_2` | `city/pieces/sidewalk_chunk.tscn` | Vereda de tramo (`MultiMesh`) | — | — |
| `Sidewalk_Tile_1` | `city/pieces/sidewalk_tile.tscn` | Baldosa de vereda (`MultiMesh`) | — | — |

Los props (`Advertising_*`, `SateliteDish`) **no tienen HP propio**: son hijos decorativos de un `Building` y, cuando éste pasa a `DAMAGED`, se desprenden como `DebrisChunk` cosméticos (masa baja, sin daño estructural). Sólo hay **dos** piezas altas para 21 torres: la variedad se consigue con escala vertical y rotación en pasos de 90° (§4.3), no con mallas nuevas.

### 2.2 Escala y verificación

Los FBX declaran `UnitScaleFactor = 1.0` y `UpAxis = Y`; por el origen del pack es casi seguro que están en **centímetros**. Procedimiento obligatorio: (1) copiar los 13 FBX a `assets/city/pieces_src/` e importarlos con los valores por defecto (`nodes/root_scale = 1.0`); (2) ejecutar `city_import_check`, que imprime el AABB agregado de cada pieza; (3) si `BuildingBlock_1` mide ~1 200 unidades de alto, fijar **`nodes/root_scale = 0.01`** en los 13 `.fbx.import` y reimportar (si midiera ~12, dejarlo en 1.0); (4) volver a ejecutar el check, donde **`BuildingBlock_1` debe medir entre 12 y 16 m**.

Los `.fbx.import` se **comiten**. Nunca se corrige la escala poniendo `scale` en el nodo de la escena: eso rompe las formas de colisión y `docs/03` prohíbe escalar cuerpos físicos.

Opciones de import comunes a las 13 piezas: `nodes/root_scale` `0.01` (a confirmar en el paso 3) con `nodes/apply_root_scale = true` para que la escala se hornee en los vértices · `nodes/root_type = "StaticBody3D"` y `nodes/root_name` con el nombre de la pieza, para que la raíz ya sea el cuerpo de colisión y los nodos sean estables en las escenas heredadas · `meshes/generate_lods = true` (60 edificios en pantalla; los enemigos usan `false`, `docs/05`) · `meshes/create_shadow_meshes = true` · `meshes/ensure_tangents = true` · `materials/extract = true` con `materials/extract_path = res://assets/city/materials/`, para que los materiales salgan a `.tres` y compartan las texturas 2K/1K · `animation/import = false` · `import_script/path = res://asset_import/import_city_piece.gd` (§2.4).

### 2.3 Texturas y presupuesto de VRAM

De los 12 PNG del pack se conservan **8**. Los cuatro `VoxelCity_CompositeBuildings_Optimized-*` se **descartan** si las cuatro `*Diffuse` cubren todas las UV de las 13 piezas, lo que se verifica al extraer los materiales (paso 2.2); si alguna pieza sí referencia un composite, se conserva **sólo ese** a 2K y se anota en `CREDITS.md`. Todas con `compress/mode = 2` (VRAM Compressed) y `mipmaps/generate = true`:

| Texturas | Destino | Cantidad | VRAM BC1 | VRAM BC7 |
|---|---|---|---|---|
| `T_Buildings_001/002Diffuse` | 2048² | 2 | 5.33 MB | 10.67 MB |
| `T_PropsDiffuse`, `T_RoadsDiffuse` | 1024² | 2 | 1.33 MB | 2.67 MB |
| `BAKE_*Emissive` (buildings 001/002, props, roads) | 1024² | 4 | 2.67 MB | 5.33 MB |
| **Total** | | **8** | **9.4 MB** | **18.6 MB** |

El reescalado se hace con `process/size_limit` (2048 o 1024) en el `.import`, no editando los PNG: el original queda intacto y el ajuste es reversible. El presupuesto del plan es **< 90 MB** y sobra margen de 4× a 9×; el check existe para atrapar el caso contrario, porque los cuatro diffuse a 4 096² sin comprimir con mipmaps son **358 MB**, cuatro veces el presupuesto por sí solos.

Ajustes adicionales: `mipmaps/generate = true` es obligatorio en 3D (evita el aliasing de las fachadas a distancia), `detect_3d/compress_to = 0` para que Godot no cambie el modo por su cuenta, y `compress/high_quality = false` por defecto (BC1/BC3), subiendo a BPTC sólo si aparecen artefactos en el grading de `docs/13`.

### 2.4 `import_city_piece.gd`

`asset_import/import_city_piece.gd`, `EditorScenePostImport`:

```gdscript
@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object
```

Responsabilidades, en orden:

1. **Garantizar la raíz `StaticBody3D`**: si `nodes/root_type` ya la creó se usa, si no se crea y se reparenta todo bajo ella. `collision_layer = 128` (capa 8 `city`), `collision_mask = 311` (capas 1,2,3,5,6,9 según `docs/02` §3.1).
2. **Forma de colisión** por tabla de nombres, determinista y revisable: `Building_3`, `BuildingBlock_*`, `Road_Chunk_5` y `Sidewalk_*` → **`BoxShape3D`** del AABB agregado (los edificios son cajas y además deben poder redimensionarse por variación de altura, §4.3); `SateliteDish` y `Advertising_*` → **`ConvexPolygonShape3D`** con `mesh.create_convex_shape(true, true)`.
3. **Mallas**: `gi_mode = GI_MODE_STATIC` y `cast_shadow = SHADOW_CASTING_SETTING_ON` en cada `MeshInstance3D`; en los props, además `visibility_range_end = 180.0` y `visibility_range_fade_mode = VISIBILITY_RANGE_FADE_SELF`.
4. **Metadatos** en la raíz: `piece_id` y `base_size` (el AABB), para que las escenas heredadas y `CityGrid` no recalculen dimensiones en runtime.
5. Asignar `owner` a todo nodo creado y devolver `scene`.

Los LOD **no** se generan aquí: los produce el importador. El runtime no expone el número de niveles, así que `city_import_check` comprueba la **opción** en el `.import`.

### 2.5 `city/pieces/*.tscn`

Cada pieza jugable es una **escena heredada** de la escena importada («Nueva escena heredada»). La raíz heredada ya es el `StaticBody3D` de la capa 8; se le asigna `script = res://city/building.gd` y se añaden los nodos de etapa:

```
tower_a (Building : StaticBody3D, capa 8, máscara 311)
├─ StageIntact (Node3D) → Mesh (malla importada, gi_mode STATIC) + Windows (emisivo)
├─ StageDamaged (Node3D, visible = false) → Mesh (misma malla + damage_overlay.gdshader)
├─ StageRubble (Node3D, visible = false) → Mesh (rubble_pile_*) + Smoke (GPUParticles3D) + Dust (FogVolume BOX)
├─ IntactShape (CollisionShape3D — BoxShape3D)
├─ RubbleShape (CollisionShape3D — BoxShape3D baja, disabled = true)
├─ DustBurst (GPUParticles3D, one_shot) + FireLight (OmniLight3D, visible = false)
└─ CollapseSound (AudioStreamPlayer3D, bus City)
```

Las piezas de calle (`road_chunk`, `sidewalk_chunk`, `sidewalk_tile`) **no** llevan `Building` ni colisión propia: se dibujan con `MultiMeshInstance3D` y el suelo lo aporta una única caja de terreno (§4.4), lo que ahorra ~120 colisionadores.

---

## 3. `Building` y etapas de destrucción (WP-20)

### 3.1 Máquina de etapas

```
INTACT  ──ratio ≤ 0.60──▶  DAMAGED  ──ratio ≤ 0.15──▶  RUBBLE (absorbente)
```

`take_damage(amount, point)`: (1) si `stage == RUBBLE` retorna de inmediato, una ruina no recibe más daño; (2) `hp = max(0.0, hp - amount)` y `CityIntegrity` recibe el delta real aplicado; (3) si `get_ratio() <= rubble_threshold` → `hp = 0.0` y transición a `RUBBLE`; (4) si no, y `get_ratio() <= damaged_threshold` con `stage == INTACT` → transición a `DAMAGED`; (5) `stage_changed(stage)` sólo en la transición.

Poner `hp = 0` al entrar en `RUBBLE` hace que la integridad de una ciudad arrasada valga exactamente **0.0** y que `Events.city_integrity_changed` sea monótona no creciente por construcción. La consecuencia es que **el coste efectivo de derribar un edificio es el 85 % de su HP nominal**:

| Perfil | `max_hp` nominal | Coste efectivo (85 %) | Con `siege_beam` (700 HP/s) |
|---|---|---|---|
| `block_low` / `block_mid` | 1 200 | 1 020 | 1.46 s |
| `tower_a` / `tower_b` | 3 500 | 2 975 | 4.25 s |

### 3.2 Presentación por etapa

**INTACT** — malla completa, ventanas emisivas encendidas (`emission_energy = 1.0`), `IntactShape` activa.

**DAMAGED** — se conmuta a `StageDamaged`. El look se consigue **sin autorar 13 mallas dañadas**: el mismo mesh con un material `damage_overlay.gdshader` que recorta huecos con ruido (`ALPHA_SCISSOR_THRESHOLD` sobre un `NoiseTexture2D` triplanar, con `damage_amount` como uniform 0–1), apaga los emisivos de ventana y oscurece el albedo con hollín en las zonas recortadas. Se encienden dos o tres `GPUParticles3D` de fuego (`amount = 24`, continuos) y la `FireLight` (naranja, parpadeo por `Tween` en bucle sobre `light_energy` 1.4 ± 0.6, período 0.35 s). La colisión **no cambia**. Los props se desprenden aquí como escombros cosméticos.

**RUBBLE** — animación de derrumbe de `collapse_seconds` (1.8 s) con `Tween`:

1. `t = 0` — `DustBurst.restart()`, `CollapseSound.play()`, `Events.camera_trauma(profile.trauma, global_position)`, y se piden `debris_count` trozos al `DebrisPool` con impulso radial hacia afuera y hacia arriba.
2. `0 → 1.8 s` — `StageIntact`/`StageDamaged` descienden `height * 0.35` y se desvanecen; `StageRubble` aparece y crece de 0.6 a 1.0.
3. `t = 1.8 s` — `IntactShape.disabled = true`, `RubbleShape.disabled = false` (caja baja de `height * 0.18`), `Smoke` y `FogVolume` activos, `destroyed(value)` y `Events.building_destroyed(global_position, value)`.

La columna de humo es un `GPUParticles3D` continuo (`amount = 48`, `lifetime = 6.0`, `draw_order = DRAW_ORDER_VIEW_DEPTH`) más un `FogVolume` local (`FOG_VOLUME_SHAPE_BOX`, `size ≈ (30, 40, 30)`, `density 0.03`) para el polvo volumétrico, ambos con `visibility_range_end = 400 m`. Las mallas de ruina (`rubble_pile_low/mid/high.mesh`) son **propias** (pipeline voxel de `docs/05` o CSG horneado): FreeSample no trae variantes dañadas. `StageRubble` y los escombros van con **`GI_MODE_DISABLED`** por el riesgo 9 del plan (popping de SDFGI con geometría que cambia).

---

## 4. `CityGrid` y `district_a`

### 4.1 Geometría de la rejilla

Celda de **24 m**. Patrón de manzana: bloques de **2×2 celdas de edificio** separados por **1 celda de calle**, con período 3; **5 bloques en X × 3 en Z** → rejilla de 15 × 9 celdas = **360 × 216 m**, con (5×2) × (3×2) = **10 × 6 = 60 edificios exactos** y 75 celdas de calle. Una celda es de calle si `x % 3 == 2` o `z % 3 == 2`. El resultado es determinista: el check no cuenta «aproximadamente 60», cuenta 60.

### 4.2 Reparto de HP

| Perfil | Cantidad | `max_hp` | Subtotal |
|---|---|---|---|
| Bajos y medios (`block_low_a/b/c`, `block_mid`) | **39** | 1 200 | 46 800 |
| Torres (`tower_a`, `tower_b`) | **21** | 3 500 | 73 500 |
| **Total** | **60** | | **120 300** |

120 300 está a **+0.25 %** de los 120 000 del plan, dentro del ±5 % exigido.

Las 21 torres se concentran en los **3 bloques centrales** (centro financiero) y los bajos ocupan la periferia: da una silueta legible desde el aire, orienta al jugador y justifica que el jefe camine hacia el centro.

Coste efectivo de arrasar la ciudad: `0.85 × 120 300 = 102 255` HP. Para que caiga en 5 min sin oposición el jefe necesita **341 HP/s** sostenidos; `docs/07` debe verificar que su mezcla de `siege_beam` (700 HP/s), `stomp` (2 500) y `walk` (900 por edificio pisado) lo alcanza. Es un punto de balance de WP-23.

### 4.3 Siembra y variación

`CityGrid.build()` con un `RandomNumberGenerator` sembrado con `seed` (que el nivel toma de `Global.round_seed`): recorre las 60 celdas de edificio en orden fijo; elige perfil según la zona (centro → torre, periferia → bajo/medio) y variante de pieza al azar entre las de ese perfil; instancia y posiciona en el centro de la celda con `yaw = randi_range(0, 3) * 90°`; y aplica una variación de altura `height_scale ∈ [0.85, 1.35]`.

**La variación de altura NO escala el cuerpo físico.** `Building.apply_variation(height_scale, yaw_steps)` escala únicamente los `MeshInstance3D` de las etapas y **reescribe** `BoxShape3D.size.y` y la posición de la forma:

```
shape.size = Vector3(base.x, base.y * height_scale, base.z)
shape_node.position.y = shape.size.y * 0.5
```

Escalar un `StaticBody3D` produce formas de colisión inconsistentes en Jolt; está prohibido por `docs/03` y verificado por revisión.

El distrito resultante se guarda como **escena concreta** `city/districts/district_a.tscn` (generada una vez con `seed = 0` y comiteada), no se genera en cada arranque: así el horneado de oclusores, la iluminación y el check son reproducibles.

### 4.4 Terreno, calles y rocas

- **Suelo**: un único `StaticBody3D` de capa **1** (`world`, máscara 2,3,6,9) con un `BoxShape3D` de `1200 × 4 × 1200 m` centrado en `y = −2` (superficie en `y = 0`). Cubre el distrito y el descampado con **un solo colisionador**; el raycast de pie del jefe (máscara `1|8` = 129) y el de LOS lo encuentran sin problema. El relieve exterior es un `PlaneMesh` de 1 200 m con material triplanar; el `HeightMapShape3D` queda para después del MVP.
- **Calles y veredas**: puramente visuales, en tres `MultiMeshInstance3D` (`road_chunk`, `sidewalk_chunk`, `sidewalk_tile`) con `gi_mode = STATIC`: **3 draw calls** para toda la red viaria.
- **Rocas y colinas**: **6** piezas (rango admitido 5–8) en el borde, a 40–90 m del perímetro, de 18–40 m de alto. Malla voxel propia o CSG horneado con `StandardMaterial3D` y `uv1_triplanar = true` (sin UV autoradas), `StaticBody3D` de capa **1** con `ConvexPolygonShape3D`, en el grupo **`city_rocks`**. Sirven de percha para el dron, de cobertura contra el `head_laser` y de punto de escalada para el jefe.

---

## 5. `CityIntegrity`

```
ratio = Σ hp_actual / Σ hp_inicial
```

Implementación **incremental**: `CityIntegrity` no vuelve a sumar los 60 edificios cada frame; `Building.take_damage()` notifica el delta aplicado y se resta de un acumulador, con `Σ hp_inicial` calculado una sola vez. `Events.city_integrity_changed(ratio)` se emite cuando `ratio` baja ≥ 0.002 o han pasado 0.25 s con un cambio pendiente. Es monótona no creciente por construcción: no hay reparación en el MVP y `RUBBLE` es absorbente. Al cruzar `defeat_ratio = 0.35` se emite `defeat_threshold_reached()` **una sola vez**; `RoundManager` (`docs/11`) escucha la señal del bus y decide la derrota — `CityIntegrity` no conoce la máquina de ronda.

**Edificio «bajo asedio»**: `CityIntegrity` mantiene, a 4 Hz, una ventana deslizante de 3 s del daño recibido por edificio. El que más acumule en la ventana, si supera `siege_min_damage` (150 HP), se marca con `mark_under_siege(true)` y el anterior se desmarca. El `Building` marcado enciende un emisivo de baliza y entra en el grupo **`buildings_under_siege`**, que `OffscreenMarkers` (`docs/12` §4.1) recorre. El coste es un `Dictionary` de 60 entradas revisado 4 veces por segundo.

Todo `Building` pertenece además al grupo **`buildings`**, que es como `RoundManager` (`docs/11` §4.2) los registra tras instanciar el distrito con `CityIntegrity.rebuild()`.

---

## 6. `DebrisPool` y `RubbleField`

`DebrisPool` es **compartido con los enemigos** (`docs/06`): un único pool por nivel, cableado por `battle_level.tscn`, con **máximo 24 `DebrisChunk` vivos**.

`DebrisChunk` es un `RigidBody3D` de capa **9** (256) con máscara **387** (capas 1,2,8,9), `gi_mode = DISABLED`, `cast_shadow = ON` y `contact_monitor = false` — quien detecta el golpe al dron es el propio dron (`docs/09`). `continuous_cd = true` sólo si `mass > 800` kg, para que un trozo de torre no atraviese el suelo. Vida de **20 s** (Anexo A), o retiro anticipado si lleva `sleeping == true` más de 2 s.

**Retiro y fusión**: al pedir el chunk número 25 se retira el más viejo con `freeze_mode = FREEZE_MODE_STATIC` y `freeze = true`, su transformada se hornea en el `RubbleField` de su malla, y el `RigidBody3D` se oculta, se limpia y vuelve a la lista libre.

`RubbleField` es un conjunto de `MultiMeshInstance3D`, **uno por malla distinta registrada**, con tope de **4 mallas** (≤ 4 draw calls): la ciudad registra dos (`debris_concrete_small/large`) y los enemigos hasta dos más. `instance_count = 512` por campo, `use_custom_data = true` (tinte por instancia), `gi_mode = DISABLED`.

`Events.camera_trauma(amount, position)` se emite una vez por derrumbe con `amount = profile.trauma`. **El emisor no atenúa por distancia**: publica el hecho («hubo un derrumbe de intensidad A en P») y el `CameraRig` aplica `trauma += amount * clampf(1 − distancia / 80, 0.15, 1)` (radio de 80 m con piso 0,15, `docs/13` §6; WP-28 corrigió acá los «120 m sin piso»). Así el bus sigue publicando hechos, como exige el Contrato de Events (`docs/02` §5.1). El sonido es un `AudioStreamPlayer3D` del propio `Building` (bus `City`, `unit_size` 60 m, `max_distance` 400 m).

---

## 7. Rendimiento

Medidas: LOD de malla por `meshes/generate_lods = true` con `rendering/mesh_lod/lod_change/threshold_pixels = 1.0` · props lejanos con `visibility_range_end = 180 m` y `FADE_SELF` · humo y niebla de ruinas a 400 m · `rendering/occlusion_culling/use_occlusion_culling = true` con **15 `OccluderInstance3D`** horneados (uno por bloque de 2×2) sobre `district_a` · calles en 3 `MultiMeshInstance3D` en vez de ~120 nodos · 1 caja de suelo en vez de ~120 colisionadores de calle · `GI_MODE_STATIC` en edificios y `DISABLED` en ruinas y escombros (riesgo 9) · `create_shadow_meshes = true`. **Presupuesto de draw calls** (el tope de WP-24 es < 900 a 1080p): 60–120 por los edificios (1–2 superficies cada uno), 3 por calles y veredas, 3 por props, ≤ 4 por `RubbleField`, ≤ 24 por escombros vivos, 8 por rocas y terreno, ~24 por el jefe, ~9 por dron y trazadores y ≤ 12 de VFX (tope de `vfx_check`) → **≈ 150–210 en total**. Queda margen de 4× para el `Environment`, las sombras en cascada y el fisheye. La medición real es de `render_check` (WP-24, `docs/15`).

---

## 8. Fuego amigo del arma

Un proyectil del jugador que impacta en la capa 8 llama a `Building.take_damage(amount, point)` con `amount = damage × city_friendly_fire_scale` = `12 × 0.5` = **6** (`docs/08` §2.7). `ProjectilePool` acumula el daño estructural causado por el jugador y lo expone con `get_friendly_fire_damage()`. Consecuencias que el diseño acepta: el jugador **puede** derribar edificios (1 020 HP efectivos / 6 = **170 impactos** para un bloque bajo, ~39 s de fuego sostenido) — caro pero posible, que es lo que hace que el castigo de puntaje importe; la integridad baja igual venga el daño de quien venga, porque `CityIntegrity` no distingue la fuente, así que la derrota por integridad < 0.35 puede provocarla el propio jugador; y el `Building` **no** recibe la identidad del atacante (el escalado lo aplica el llamador), con lo que `take_damage(amount, point)` queda estable para enemigos y jugador. Penalización de puntaje **propuesta**: `−0.02 × friendly_fire_damage`, a fijar en `docs/11`.

---

## 9. Interfaz pública

### 9.1 `Building`

```gdscript
class_name Building extends StaticBody3D
enum Stage { INTACT, DAMAGED, RUBBLE }
signal stage_changed(stage: Stage)
signal destroyed(value: int)
signal damage_taken(amount: float, point: Vector3)
@export var profile: BuildingProfile
@export var stage_intact: Node3D                   # + stage_damaged, stage_rubble
@export var intact_shape: CollisionShape3D         # + rubble_shape
@export var fire_light: OmniLight3D                # + dust_burst, collapse_sound
@export var debris_pool: DebrisPool
var hp: float
var stage: Stage = Stage.INTACT
var value: int
func take_damage(amount: float, point: Vector3) -> void
func get_ratio() -> float
func get_max_hp() -> float
func is_destroyed() -> bool
func mark_under_siege(active: bool) -> void
func apply_variation(height_scale: float, yaw_steps: int) -> void
func reset() -> void
```

### 9.2 `BuildingProfile`

```gdscript
class_name BuildingProfile extends Resource
@export var id: StringName = &"block_low"
@export_range(1.0, 50000.0) var max_hp: float = 1200.0
@export_range(0.0, 1.0) var damaged_threshold: float = 0.60
@export_range(0.0, 1.0) var rubble_threshold: float = 0.15
@export var mesh_intact: Mesh                      # + mesh_damaged, mesh_rubble
@export_range(0, 32) var debris_count_min: int = 4
@export_range(0, 32) var debris_count_max: int = 8
@export_range(1.0, 10000.0) var debris_mass: float = 450.0
@export_range(0.0, 5.0) var dust_scale: float = 1.0
@export_range(0, 10000) var value: int = 100
@export_range(0.1, 10.0) var collapse_seconds: float = 1.8
@export_range(0.0, 2.0) var trauma: float = 0.65
@export_range(1.0, 200.0) var height: float = 14.0
@export_range(0.0, 1.0) var rubble_height_factor: float = 0.18
```

Perfiles iniciales: `city/profiles/block_low.tres`, `block_mid.tres`, `tower_a.tres`, `tower_b.tres`.

### 9.3 `CityGrid`, `CityIntegrity`, `DebrisPool`, `RubbleField`

```gdscript
class_name CityGrid extends Node3D
@export_range(1.0, 100.0) var cell_size: float = 24.0
@export_range(1, 20) var block_cols: int = 5       # + block_rows 3, block_span 2
@export var seed: int = 0
@export var low_pieces: Array[PackedScene]         # + tall_pieces
@export var low_profiles: Array[BuildingProfile]   # + tall_profiles
@export_range(0, 200) var tall_count: int = 21
@export var debris_pool: DebrisPool
func build() -> void
func get_buildings() -> Array[Building]
func get_building_at(cell: Vector2i) -> Building
func get_extent() -> Vector2                       # (360, 216) m
func is_street_cell(cell: Vector2i) -> bool

class_name CityIntegrity extends Node
signal integrity_changed(ratio: float)
signal defeat_threshold_reached()
@export var grid: CityGrid
@export_range(0.0, 1.0) var defeat_ratio: float = 0.35
@export_range(0.0, 10.0) var siege_window: float = 3.0
@export_range(0.0, 5000.0) var siege_min_damage: float = 150.0
func rebuild() -> void                             # alias documentado: reset() + alta de todo el grupo "buildings"
func register(building: Building) -> void
func get_ratio() -> float                          # CANÓNICO: lo usan docs/11 y docs/12
func ratio() -> float                              # alias documentado de get_ratio()
func get_total_hp() -> float
func get_initial_hp() -> float
func get_under_siege() -> Building                 # null si no hay
func get_destroyed_count() -> int
func reset() -> void

class_name DebrisPool extends Node3D
const MAX_LIVE: int = 24
@export var rubble_field: RubbleField
@export_range(1.0, 120.0) var debris_lifetime: float = 20.0
func request(mesh: Mesh, shape: Shape3D, xform: Transform3D, mass: float, impulse: Vector3, lifetime: float) -> DebrisChunk
# adopt() reparenta nodos YA EXISTENTES bajo el chunk: es la forma que usa el
# desprendimiento de partes de enemigo (docs/06 §4.1). Firma cerrada, no negociable.
func adopt(mesh: MeshInstance3D, body: PhysicsBody3D, mass: float,
        impulse: Vector3, lifetime: float) -> DebrisChunk
func get_live_count() -> int
func retire_oldest() -> void
func clear() -> void

class_name RubbleField extends Node3D
func register_mesh(mesh: Mesh) -> int              # −1 si ya hay 4 campos
func bake(mesh_index: int, xform: Transform3D, tint: Color) -> void
func get_field_count() -> int
func get_instance_count(mesh_index: int) -> int
func clear() -> void
```

### 9.4 Capas de física usadas

| Elemento | Capa | Máscara | Valores |
|---|---|---|---|
| `Building` (intacto y ruina) | 8 `city` | 1,2,3,5,6,9 | layer **128** / mask **311** |
| Suelo y rocas | 1 `world` | 2,3,6,9 | layer **1** / mask **294** (`2+4+32+256`) |
| `DebrisChunk` | 9 `debris` | 1,2,8,9 | layer **256** / mask **387** |
| Consulta de pie y de LOS del jefe | — | 1,8 | mask **129** |
| Consulta de espacio libre de pilas (`docs/09`) | — | 8,9 | mask **384** |

### 9.5 Eventos publicados

| Señal de `Events` | Firma canónica de este doc | Emitida por |
|---|---|---|
| `building_destroyed` | `(position: Vector3, value: int)` | `Building` |
| `city_integrity_changed` | `(ratio: float)` | `CityIntegrity` — coincide con `docs/11` y `docs/12` |
| `camera_trauma` | `(amount: float, position: Vector3)` | `Building` (derrumbe) |

> **Reconciliación cerrada (2026-09-19)**: gana la forma de **dos** argumentos, `camera_trauma(amount: float, position: Vector3)`, ya fijada en el Contrato de Events (`docs/02` §5.1). `docs/06` y `docs/07` pasaron a emitir la posición. El motivo es el de siempre: sin ella el emisor tendría que conocer dónde está la cámara para atenuar, y el bus dejaría de publicar hechos.

---

## 10. Parámetros y valores iniciales

Del **plan (§4.7 y Anexos A–C del borrador; ver `docs/00` §4.1)** (valores cerrados): celda de 24 m · **60 edificios** · HP 1 200 (bajos) y 3 500 (torres) con total ≈ 120 000 · umbrales de etapa 0.60 / 0.15 · `debris_count` 4–8 por transición · `debris_lifetime` 20 s · `defeat_ratio` 0.35 · `MAX_LIVE` del pool 24 · rocas 5–8 · texturas 2 048² (edificios) y 1 024² (props, calles, emissive) VRAM Compressed con mipmaps · presupuesto de VRAM < 90 MB.

**Propuestas de este documento**:

| Parámetro | Valor | Justificación |
|---|---|---|
| Rejilla | 15 × 9 celdas = 360 × 216 m | única disposición que da **60 edificios exactos** con manzanas de 2×2 |
| Reparto | 39 bajos/medios + 21 torres = **120 300 HP** | +0.25 % sobre los 120 000 del plan |
| `debris_mass` (bajo / torre) | 450 / 2 000 kg | mapea a 17.1 y 28.0 de daño al dron (`docs/09`) |
| `collapse_seconds` | 1.8 s | deja margen sobrado frente al criterio de < 6 s |
| `trauma` (bajo / torre) | 0.65 / 0.85 | una torre se siente más que un bloque |
| `value` (bajo / torre) | 100 / 300 | pesa el puntaje y la prioridad de «bajo asedio» |
| `rubble_height_factor` | 0.18 | la ruina sigue siendo obstáculo, no pared |
| `siege_window` / `siege_min_damage` | 3.0 s / 150 HP | evita que la baliza salte entre edificios |
| Campos de `RubbleField` | ≤ 4, 512 instancias | 2 para la ciudad y 2 para los enemigos |
| Rocas / suelo | 6 de 18–40 m / caja 1 200 × 4 × 1 200 m capa 1 | un solo colisionador para todo el terreno |
| `nodes/root_scale` | 0.01 (a confirmar en §2.2) | centímetros → metros |
| `visibility_range_end` props / humo | 180 m / 400 m | recorta el grueso de los draw calls lejanos |
| Oclusores | 15, uno por bloque | horneados sobre `district_a` |
| `city_friendly_fire_scale` | 0.5 | ver §8 y `docs/08` |

---

## 11. Criterios de aceptación y checks headless

Comando base:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn
```

### 11.1 `city_import_check` (WP-13)

**Archivo**: `tools/city_import_check.tscn` + `tools/city_import_check.gd`.

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `pieces_present` | Las **13** rutas de `assets/city/pieces_src/*.fbx` existen y `load()` devuelve una `PackedScene` instanciable |
| 2 | `root_is_body` | La raíz de cada pieza es un `StaticBody3D` con `collision_layer == 128` y `collision_mask == 311` |
| 3 | `has_shape` | ≥ 1 `CollisionShape3D` con `shape != null`; `BoxShape3D` en las 6 de edificio y las 3 de calle, `ConvexPolygonShape3D` en `SateliteDish` y `Advertising_*` |
| 4 | `scale_reference` | AABB agregado de los `MeshInstance3D` de `BuildingBlock_1`: `size.y` ∈ **[12, 16] m** |
| 5 | `scale_sanity` | Toda pieza con `0.2 m < size.y < 120 m` (atrapa el factor 100 en cualquier dirección) |
| 6 | `import_options` | En cada `<pieza>.fbx.import` (`ConfigFile`): `nodes/root_scale` igual al valor fijado, `meshes/generate_lods == true`, `meshes/create_shadow_meshes == true`, `animation/import == false`, `import_script/path` → `import_city_piece.gd` |
| 7 | `gi_mode` | Todos los `MeshInstance3D` con `gi_mode == GI_MODE_STATIC`; props con `visibility_range_end == 180` y `FADE_SELF` |
| 8 | `texture_settings` | En cada `<png>.import` bajo `assets/city/`: `compress/mode == 2`, `mipmaps/generate == true`, `process/size_limit` ≤ 2048 en los diffuse de edificio y ≤ 1024 en props, calles y emissive |
| 9 | `texture_vram` | Estimación analítica `w × h × bpp × 4/3` desde `process/size_limit` y el formato implicado: suma **< 90 MB** |
| 10 | `composites_absent` | Ningún `VoxelCity_CompositeBuildings_Optimized-*` en `assets/city/`, o bien cuenta en el presupuesto del sub-check 9 |
| 11 | `restore` | No escribe en `user://` ni modifica ningún `.import` |

> El VRAM se estima leyendo los `.import` con `ConfigFile`, no consultando al `RenderingServer`: con `--headless` el controlador de render es nulo y sus contadores no son fiables. Además así se verifica la **intención** configurada, que es lo que hay que conservar en el repo.

### 11.2 `city_check` (WP-20)

**Archivo**: `tools/city_check.tscn` + `tools/city_check.gd`. Instancia `city/districts/district_a.tscn` y avanza el tiempo sintéticamente llamando a `_physics_process(1.0/100.0)` en bucle (los temporizadores de gameplay son acumuladores, no `Timer`).

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `building_count` | `CityGrid.get_buildings().size() == 60`, todos en el grupo `buildings` |
| 2 | `hp_total` | `Σ profile.max_hp == 120300`, dentro de **120 000 ±5 %** → [114 000, 126 000] |
| 3 | `hp_mix` | **39** edificios con `max_hp == 1200` y **21** con `max_hp == 3500` |
| 4 | `grid_layout` | Extensión `(360, 216) m`; ningún edificio en celda de calle; distancia mínima entre centros ≥ 24 m |
| 5 | `no_body_scale` | Ningún `Building` con `scale != Vector3.ONE`; toda variación de altura reflejada en `BoxShape3D.size.y` |
| 6 | `stages` | Daño progresivo → `stage_changed(DAMAGED)` al cruzar 0.60 y `(RUBBLE)` al cruzar 0.15; `destroyed` **una** vez; `take_damage` posterior no cambia nada |
| 7 | `stage_visuals` | En `RUBBLE`: `intact_shape.disabled == true`, `rubble_shape.disabled == false`, sólo `stage_rubble.visible` |
| 8 | `collapse_time` | Desde el cruce del umbral hasta (`stage == RUBBLE` **y** todos sus `DebrisChunk` dormidos, retirados o congelados): **< 6 s** |
| 9 | `integrity_monotonic` | Destruyendo los 60 con semilla fija y muestreando `Events.city_integrity_changed`: sucesión monótona no creciente, valor final ≤ 0.001 |
| 10 | `integrity_defeat` | `defeat_threshold_reached()` emitido **exactamente una** vez, al cruzar 0.35 |
| 11 | `integrity_incremental` | `ratio()` coincide con `Σ hp / Σ hp_inicial` recalculado a mano en 5 puntos (±1e−4): el acumulador no deriva |
| 12 | `debris_cap` | Con 10 edificios destruidos seguidos, `get_live_count() <= 24` en **todos** los ticks |
| 13 | `debris_fusion` | El chunk retirado aparece en `RubbleField` y vuelve a la lista libre; tras `clear()`, 0 vivos y sin huérfanos; `get_field_count() <= 4` |
| 15 | `trauma` | Un `camera_trauma` por derrumbe, con `amount == profile.trauma` y `position` la del edificio; el emisor **no** atenúa por distancia |
| 16 | `rocks_ground` | 5–8 nodos en el grupo `city_rocks` con `collision_layer == 1`; un `StaticBody3D` de capa 1 cuyo `BoxShape3D` cubre ≥ 360 × 216 m con la cara superior en `y == 0 ±0.01` |
| 18 | `street_batching` | Exactamente **3** `MultiMeshInstance3D` para calzada y veredas; **0** colisionadores propios de calle |
| 19 | `friendly_fire` | `take_damage(6.0, p)` × 170 sobre un bloque bajo → llega a `RUBBLE`; el daño registrado coincide con el aplicado |
| 20 | `restore` | No escribe en `user://`; deja `Global.round_seed` como estaba antes de `quit()` |

Ambos checks imprimen una línea `[PASS]`/`[FAIL]` por sub-check y un resumen; `quit(0)` si todo pasa, `quit(1)` con el recuento de fallos si no.

---

## 12. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **Firma de `camera_trauma`** | **Cerrado (2026-09-19)**: dos argumentos `(amount, position)` en `docs/02` §5.1; los cuatro emisores (06, 07, 09, 10) ya usan esa forma |
| 2 | **Escala real de los FBX** (riesgo 8 del plan) | Abierto hasta el paso 3 de §2.2. Se mide primero y se fija después; `city_import_check` bloquea el WP si `BuildingBlock_1` no cae en 12–16 m |
| 3 | **Licencia del pack FreeSample** (riesgo 11) | Abierto; lo cierra `docs/16` antes de publicar. No se redistribuye el ZIP, en el repo sólo quedan los derivados |
| 4 | **Mallas dañadas y de ruina inexistentes en el pack** | **Decidido**: `DAMAGED` por shader (`damage_overlay.gdshader`), no por mallas nuevas; si no convence en el checkpoint 3, la alternativa es autorar 4 mallas en Blender. Las `rubble_pile_*` son propias y dependen de WP-12 o de un horneado CSG: bloquean el acabado visual de `RUBBLE`, no su lógica |
| 5 | Composites de textura y sólo 2 piezas altas para 21 torres | Los composites se descartan si ningún material los referencia (si alguno los usa, +5 MB, muy por debajo de 90). La repetición de torres se mitiga con escala 0.85–1.35 y rotación de 90° |
| 6 | **SDFGI y geometría que cambia** (riesgo 9) | Mitigado: ruinas y escombros con `gi_mode = DISABLED`. La prueba A/B con `ReflectionProbe` locales es de WP-24 |
| 7 | `DebrisChunk` grandes y tunneling contra Jolt (riesgo 6) | Mitigado con `continuous_cd` sobre 800 kg; si aparecen trozos que atraviesan el suelo, se sube el umbral o se baja `debris_mass` |
| 8 | 341 HP/s para que la ciudad caiga en 5 min | Abierto; lo verifica `docs/07` y lo ajusta WP-23. Palancas: `siege_beam`, cooldowns, o bajar el HP total |
| 9 | El jugador puede perder por su propio fuego amigo | **Aceptado como diseño**: 170 impactos por bloque bajo lo hacen improbable por accidente y significativo si se abusa |
| 10 | `district_a` comiteada como escena concreta | **Decidido**: `CityGrid` genera una vez con `seed = 0` y se guarda. Permite hornear oclusores y hace reproducible el check |
| 11 | 24 escombros rígidos + el jefe en el mismo tick | Presupuesto de física < 2 ms/tick (`docs/15`). Si se supera, la palanca es bajar `MAX_LIVE` a 16 antes que tocar el jefe |

---

## 13. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — capas y máscaras, ajustes de render (occlusion culling, LOD), señales de `Events`. · `docs/05-pipeline-voxel.md` — mallas propias de ruina y rocas.
- `docs/06-framework-de-enemigos.md` — `DebrisPool.adopt()` y `RubbleField.register_mesh()`/`bake()` compartidos, `EnemyPart.detach()`, raycast de pie con máscara `1|8`, `Building.take_damage(crush_damage, ...)` al trepar. · `docs/07-arachnodroid.md` — `siege_beam`, `stomp`, `walk` y `climb`: el ritmo real de destrucción.
- `docs/08-combate-y-armas.md` — fuego amigo, `city_friendly_fire_scale`, `friendly_fire_damage`, impactos y decals. · `docs/09-energia-y-danio.md` — daño de los escombros al dron, espacio libre de las pilas en capas 8 y 9.
- `docs/11-rondas-y-objetivos.md` — derrota por `city_integrity_changed < 0.35`, puntaje `1000 · integridad`, grupo `buildings`, `rebuild()`. · `docs/12-interfaz-y-hud.md` — `CityBar`, grupo `buildings_under_siege`, `OffscreenMarkers`.
- `docs/13-identidad-visual-y-audio.md` — `environment_battle.tres`, `FogVolume`, humo, bus `City`, atenuación del trauma. · `docs/15-verificacion-y-ci.md` — checks y draw calls. · `docs/16-licencias-y-atribucion.md` — licencia del pack.
