# Narrativa — Drone Survivor

> Estado: borrador v1 · Fecha: 2026-09-20 · Base de la trama, el tono y la coherencia entre sistemas · Ver `identidad-visual-opciones.md` y `docs/13-identidad-visual-y-audio.md`

## 1. Premisa

Hace años que los lugareños se defienden. Los ataques como las estaciones: sin aviso y sin apuro, son esperados. No mandan soldados; mandan autómatas. Es barato.

Los ataques no son al azar. Buscan lo que sostiene a una ciudad cuando todo lo demás falla: la escuela, el hospital, el club, el local donde la gente se junta a organizarse. Quien los planifica lo sabe. No viene a ganar una guerra; viene a borrar un pueblo. Identifica el centro, carga las coordenadas y despacha una unidad de destrucción urbana.

Con recursos limitados, nos defendemos como podemos: con lo que hay, con lo que sobra, con lo que alguien arregló anoche en la cocina.

## 2. El mundo

**La ciudad.** Un pueblo de ruta: la ruta lo atraviesa y sigue hacia el horizonte, casas bajas con frente a la calle en cuadras que no son iguales, unos pocos edificios medianos y la escuela junto a la ruta, en el centro; campo alrededor y un caserío más lejos. Carteles de una época en que había algo que vender. Antenas en las azoteas: el pueblo se comunica por radio porque la red no es de fiar. Esto aún no son ruinas. *(Redacción de P2b, 2026-09-21: el nivel dejó de ser una rejilla en medio de la nada.)*

**La gente.** Nadie pelea de uniforme. Quien pilotea hoy fue ayer técnico, mecánico, artista, panadero. La defensa no es un ejército; es un turno más del barrio.

**El taller.** Un local con persiana a medio bajar donde se arman los drones. Cuando uno cae, sale otro, y el que sale es un poco peor que el anterior, porque las piezas buenas se acaban antes que la noche.

## 3. El enemigo

No tiene rostro ni lo va a tener. Nunca aparece un piloto, un general, una bandera. Solo llegan sus máquinas, scripts y algoritmos con piel de metal.

**Las unidades de destrucción urbana** son colosos autónomos, negros y de luces frías. Están hechos para una sola tarea: llegar hasta un punto y generar el mayor estrago posible.

La primera que conoce el jugador es el **Arachnodroid**: cuatro patas, treinta metros, un haz que corta edificios como quien pasa una regla. Después vendrán otras, cada una con un oficio: artillería que se ancla, brutos que embisten, soldados que usan la ciudad como cobertura, mulas que descargan más máquinas. Todas comparten la misma indiferencia.

**Por qué las mandan.** Porque es barato, y porque lo que buscan borrar no es un edificio sino un tejido. Una escuela se reconstruye; pero primero hay que organizarse, pero antes sobrevivir.

## 4. El dron y quien lo pilotea

El dron es chico, ruidoso y honesto. No tiene blindaje ni mira inteligente; tiene una cámara con lente ojo de pez, dos armas y una batería que dura lo que dura. Lo que ve el jugador es exactamente lo que ve el dron: una señal de video con viñeta, ruido y color que se corre en los bordes.

Quien pilotea no es un héroe; solo está de turno. Cuando el dron cae, no hay pantalla de muerte: hay unos segundos de estática, y alguien del taller le alcanza otro.

## 5. La alerta (antes de cada nivel)

No hay cinemática. Hay un monitor.

Cada nivel empieza con lo que ve quien está de turno: una pantalla vieja del taller, ámbar sobre negro, que muestra una alerta. Poca información y ninguna de más: un mapa del barrio dibujado en trazo simple, con el edificio a defender resaltado y su nombre al lado («Proteger: Escuela»); en un rincón, la palabra **ALERTA**; abajo, el enemigo que viene, escrito como lo escribiría una máquina («Enemigo: ARACHNODROID»). Nada de fichas, ni de biografías, ni de discursos. Es un aviso de vigilancia, no un briefing militar.

Lo que dice la pantalla está en las dos voces: lo nuestro en ámbar y castellano llano; el nombre del enemigo en cian y en código. Después la imagen cae a estática un instante y aparece la señal del dron, ya en el aire, en el vuelo de salida desde la azotea. El jugador nunca deja de mirar una pantalla: primero la del taller, después la del dron.

## 6. Temas

- **Asimetría.** Ellos gastan máquinas; nosotros gastamos noches. El juego nunca iguala las fuerzas, solo las hace legibles.
- **Cuidado.** Lo que se defiende no es un puntaje: es una escuela con nombre, un hospital con luces prendidas. La ciudad es un personaje y se la ve sufrir.
- **Persistencia.** Ganar no es terminar la guerra; es que mañana haya algo en pie. Cada ronda es una noche más.

## 7. Tono y lenguaje

- **Registro.** Sobrio, cercano, de crónica social. Sin épica de guerra ni jerga militar del lado propio. Frases cortas. Voseo en todo texto del jugador («Sostené la posición», «Centrá los sticks»).
- **Dos voces.** Lo propio habla en castellano llano y con calor (ámbar). Lo enemigo habla en códigos, mayúsculas y nombres técnicos (cian): `PISOTÓN`, `HAZ DE ASEDIO`, `AUTODESTRUCCIÓN`. La interfaz ya separa estas voces por color; el texto debe separarlas por tono.
- **Sin discurso.** La trama no se explica en cinemáticas. Se cuenta con lo que se ve: qué edificios caen, quién dejó las pilas, qué queda en pie al final.

## 8. Cómo se traduce al juego

| Elemento narrativo | Sistema existente | Cómo se lee en pantalla |
|---|---|---|
| «Lo que queda en pie» | `CityBar` (barra de ciudad) | La barra no mide puntos: mide barrio. Etiqueta propuesta: **EN PIE** |
| Centros sociales, escuelas, hospitales | Ciudad destructible y objetivos de ronda | Edificios con nombre y prioridad; perderlos pesa más que perder el dron |
| Los vecinos dejan pilas cargadas | Puestos de pilas en azoteas | Pilas junto a antenas y tanques de agua, donde alguien pudo subir |
| El taller arma otro dron | Respawn con penalización | Estática breve, sin pantalla de muerte, contador de drones del taller |
| La hora en que la luz se va | Anochecer de `environment_battle.tres` | Cada ronda empieza con la última luz; la ciudad enciende ventanas |
| La máquina sin cara | Colosos negros con emisivos cian | Nunca se ve al enemigo humano; los códigos de ataque son su única voz |
| Una pantalla que tiembla | `fpv_overlay.gdshader`, trauma de cámara | Viñeta, ruido y aberración: el jugador ve una señal, no un mundo |
| Ellos hablan en códigos | Nombres de ataque (`ATK_*`), fases del jefe | Cian, mayúsculas, sin adjetivos |
| Nosotros hablamos llano | Textos de HUD y menús | Ámbar, voseo, frases cortas |
| La alerta en el monitor del taller | Pantalla previa al nivel (antes de `INTRO`) | Mapa simple del barrio, edificio a proteger resaltado con nombre, ALERTA, nombre del enemigo en cian; estática y corte a la señal del dron |
| El travelling de 12 s de la intro | `INTRO` del `RoundManager` | Es el vuelo de salida desde la azotea hacia la silueta del coloso |
| Ganar es que haya mañana | `VICTORY` y `result_card` | El resultado lista qué quedó en pie antes que el puntaje |

## 9. Decisiones abiertas

- Nombre en pantalla de la ciudad y del barrio del MVP (`district_a`). Propuesta: nombres cotidianos, sin épica (un barrio, no una fortaleza).
- Si los centros protegidos llevan nombre propio («Escuela 12», «Hospital del Norte») o solo tipo. El nombre propio pesa más; cuesta poco.
- Cómo nombrar al bando enemigo en los textos: propuesta, **no nombrarlo nunca**. Solo «del otro lado» y los códigos de sus máquinas.

## 10. Semilla (texto original)

> Los nativos lleva defendiendose hace varios años ante ataques recurrentes. Envían autómatas para generar estragos. Es barato.
> Ataques sistemáticos sobre centros sociales, centros de organización, escuelas, hospitales.
> Los enemigos, genocidas, asesinos identifican estos centros y envían una unidad de destrucción urbana.
> Los recursos de mi pueblo son limitados, nos defendemos como podemos
