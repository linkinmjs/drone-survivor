# Identidad visual — opciones a partir de la narrativa

> Estado: propuesta v1 · Fecha: 2026-09-20 · Depende de: `narrativa.md`, `docs/13-identidad-visual-y-audio.md` · Objetivo: elegir **una** dirección y bajarla a doc 13

## 1. Lo que ya tenemos y condiciona todo

| Asset / sistema | Qué impone |
|---|---|
| VoxelCity (edificios, carteles publicitarios, antena parabólica, calles) | Ciudad de bloques legibles, texturas planas, ventanas emisivas horneadas. Los carteles y antenas son material narrativo gratis |
| Nueve mechas voxel (Arachnodroid primero) | Siluetas macizas y negras con emisivos saturados. Se leen por contorno, no por detalle |
| Dron voxel con paleta propia | Debe verse «armado a mano»: colores de pieza suelta, no de fábrica |
| Overlay FPV (viñeta, ruido, aberración, ojo de pez) | Todo se ve a través de una señal. La imperfección es parte del estilo, no un defecto |
| Paleta `UIPalette`: ámbar propio, cian enemigo | Dos voces por color. Ya decidido en doc 13 y coincide con la narrativa |
| Fuentes: Chakra Petch / Barlow Semi Condensed / JetBrains Mono (+ Recursive) | Display angosto, texto denso, mono para readouts |
| VFX por pool, ≤ 12 emisores | Efectos pocos y claros; nada de partículas decorativas |
| Música en tres stems (ambient / tension / combat) | La intensidad cambia por capas, no por cortes |
| Boot «Ominoso» | Identidad de estudio, fija |

Regla común a las tres opciones: **lo nuestro es cálido e imperfecto; lo de ellos es frío y exacto.** Ese contraste sostiene la trama sin una sola línea de diálogo.

## 2. Opción A — «Última luz» (anochecer, ámbar y cian) — *recomendada*

**Idea.** Los ataques llegan a la hora en que la luz se va. La ciudad enciende ventanas mientras el cielo se apaga; el coloso entra a contraluz, negro sobre naranja, con los visores cian ya prendidos.

| Capa | Cómo se ve |
|---|---|
| Entorno | Lo actual (`environment_battle.tres`): cielo de anochecer, sol bajo, niebla de profundidad suave. Ventanas cálidas (ámbar/naranja sucio), carteles con luz de tubo a medio fallar |
| Enemigos | Negro mate, emisivos cian en visores y articulaciones; naranja solo en respiraderos cuando están dañados (la máquina «sangra» calor) |
| Dron | Paleta de pieza suelta: chasis gris, un brazo rojo, otro negro, cinta en un motor. Se lee como reparado |
| HUD | Ámbar sobre la señal, mono, contorno oscuro. Cajas de objetivo cian. Punto REC rojo. Ruido y viñeta moderados |
| UI de menús | Oscura, líneas de 1 px, ámbar de acento. Un toque de «hecho a mano»: encabezados como etiquetas de rotulador, no como títulos de consola militar |
| VFX | Chispas cálidas al impactar en la ciudad, chispas cian al dar en punto débil. El polvo de las pisadas es lo más grande que hay en pantalla |
| Audio | Ambient con ciudad dormida y radio lejana; combat con metales secos, sin épica orquestal |
| Tipografía | Chakra Petch para códigos enemigos y títulos; Barlow para lo que dice la gente; JetBrains Mono para readouts |

- **Coherencia con la narrativa:** alta. La «última luz» es literal; ventanas cálidas = la gente; luces frías = la máquina.
- **Costo:** casi nulo, es la dirección de doc 13 con nombres y significado. Solo pide ajustar la paleta del dron y el tono de los encabezados de UI.
- **Riesgo:** el anochecer ya dio problemas de exposición (WP-24); está resuelto pero hay que mantenerlo.

## 3. Opción B — «Vigilia» (noche cerrada, fósforo)

**Idea.** El barrio racionó la luz. La ciudad está casi a oscuras, con pocas ventanas prendidas, y los colosos traen su propia luz: son lo único brillante en el horizonte. El jugador ve por unas gafas FPV viejas, casi monocromas.

| Capa | Cómo se ve |
|---|---|
| Entorno | Noche azul muy oscura, ventanas escasas y cálidas, carteles apagados salvo uno o dos. Haces de reflector desde azoteas |
| Enemigos | Siluetas casi invisibles hasta que se mueven; los emisivos cian son la única guía. Reflectores del barrio los «pintan» al acercarse |
| Dron | Mismo que A, pero con una luz de posición ámbar que parpadea |
| HUD | Monocromo ámbar o verde fósforo, con scanlines y ruido más fuertes. La señal se degrada al recibir daño |
| UI de menús | Igual que A, algo más contrastada |
| VFX | Fogonazos y chispas ganan protagonismo: en la oscuridad cada impacto ilumina la fachada |
| Audio | Ambient casi vacío (viento, un perro, radio); combat entra tarde y fuerte |

- **Coherencia con la narrativa:** muy alta en tensión y escasez; algo menos en «ciudad viva».
- **Costo:** medio. Reajustar entorno, sol y exposición en `build_environment.gd`; overlay FPV más agresivo; luces de reflector nuevas (2 a 4 `SpotLight3D`).
- **Riesgo:** legibilidad. Voxel negro sobre cielo negro exige luz de contorno o niebla clara detrás del coloso, y las pisadas y edificios que caen se ven peor. Más fatiga visual en partidas largas.

## 4. Opción C — «Ceniza» (amanecer pálido, desaturado)

**Idea.** El día después. Cielo blanco, polvo en el aire, sol bajo y frío. Los colosos son manchas negras contra la niebla; la ciudad, gris con manchas de color donde alguien pintó una persiana.

| Capa | Cómo se ve |
|---|---|
| Entorno | Amanecer lechoso, niebla volumétrica densa, sombras largas y suaves. Saturación general baja; el color vive solo en la gente (persianas, carteles, ropa tendida) |
| Enemigos | Silueta negra perfecta contra el cielo pálido. Emisivos cian apenas visibles de día: se muestran como reflejo en el polvo |
| Dron | Colores más vivos que el mundo: es de los pocos objetos «con color» |
| HUD | Casi blanco, con rojo para peligro y ámbar solo para foco. Ruido fino, poca viñeta |
| UI de menús | Gris azulado claro sobre fondo oscuro, más sobria |
| VFX | Polvo y ceniza mandan: derrumbes enormes y lentos. Las chispas pierden peso |
| Audio | Ambient con viento y campanas lejanas; combat con percusión seca y pocos metales |

- **Coherencia con la narrativa:** alta en lo «social» y melancólico; es la más cercana a la crónica.
- **Costo:** alto. Nuevo cielo, nueva exposición, niebla volumétrica cara con SDFGI; los emisivos cian (que hoy guían al jugador hacia los puntos débiles) dejan de leerse de día y habría que reemplazarlos por marcadores de HUD.
- **Riesgo:** pierde la separación por color que ya sostiene el combate. Lo pálido cansa menos pero comunica menos.

## 5. Comparación

| Criterio | A · Última luz | B · Vigilia | C · Ceniza |
|---|---|---|---|
| Legibilidad de siluetas | alta | baja | muy alta |
| Legibilidad de puntos débiles (cian) | alta | muy alta | baja |
| Ciudad como personaje vivo | alta | media | alta |
| Tensión y escasez | media | muy alta | media |
| Coste sobre lo ya hecho | bajo | medio | alto |
| Riesgo técnico | bajo | medio | alto |

## 6. Recomendación

**Opción A como base, con dos préstamos de B:**

1. **La señal se degrada con el daño.** Al perder vida, el overlay FPV suma ruido y scanlines; al respawnear, unos segundos de estática. Cuenta «una pantalla que tiembla» sin una línea de texto.
2. **Racionamiento visible.** No todas las ventanas prendidas: bloques enteros a oscuras y otros encendidos, para que la ciudad se vea viva pero pobre. Es un ajuste del bake de ventanas, no de iluminación.

Tres reglas de coherencia que valen para cualquier opción:

- **Nada enemigo es cálido; nada propio es cian.** Vale para UI, VFX, luces y sonido (los servos enemigos suenan limpios; el dron suena a hojalata).
- **Lo propio tiene imperfección.** Paleta de pieza suelta en el dron, encabezados de UI con aire de rotulador, ruido en la señal. Lo enemigo es exacto: geometría limpia, luces constantes, códigos en mayúscula.
- **La ciudad se muestra antes que el puntaje.** En el HUD (`EN PIE`), en la intro (el vuelo de salida) y en el resultado (qué quedó).

## 7. Qué cambiaría en doc 13 si se aprueba A

- §2.1 Premisa: incorporar la lectura narrativa (última luz, dos voces, imperfección propia).
- §2.2 Paleta: sin cambios de valores; añadir la nota de uso «ámbar = gente, cian = máquina».
- §2.3 Tipografía: asignar roles por voz (Chakra Petch = códigos enemigos y títulos; Barlow = voz propia).
- Dron: definir la paleta de pieza suelta en `assets/drone/drone_quad_palette.png`.
- §7 Overlay: parámetro de degradación por daño y estática de respawn.
- Ciudad: bake de ventanas con racionamiento por bloque.
- HUD: renombrar la etiqueta de `CityBar` a `EN PIE` / `STANDING` en `translations.csv`.
