// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Estática de señal perdida (`docs/13` §1, nota «Decisión de identidad» del
// checkpoint 3b; `docs/narrativa` §4 y §8).
//
// Cuando el dron cae **no hay pantalla de muerte**: hay unos segundos de
// estática y alguien del taller le alcanza otro. Este shader es esa estática, y
// por eso vive en el HUD de combate y no en el post de la cámara: lo que se
// corta es el **enlace de video**, no el mundo.
//
// Tres capas, ninguna con bucles:
//
// 1. **Ruido blanco a pasos.** Un hash entero por celda de `grain_px` píxeles,
//    resorteado cuando `clock * time_scale` cruza un entero. El salto es a
//    propósito: un televisor roto redibuja el cuadro, no lo arrastra, y un ruido
//    que se desliza se lee como niebla.
// 2. **Barras que ruedan.** Una ancha que aclara y otra fina —siete veces más
//    densa y en sentido contrario— que corta. Van sobre [code]SCREEN_UV.y[/code]
//    para que rueden por la pantalla entera a cualquier resolución.
// 3. **Caída a negro.** Del `BLACKOUT_START` del recorrido en adelante el color
//    se apaga hasta el negro, así que el último cuadro de la ráfaga es opaco y
//    el corte al video nuevo es seco.
//
// El reloj llega por `clock` y **no** se toma de `TIME`: el `CombatHUD` avanza a
// sus componentes con un delta propio, y `combat_hud_check` lo congela para
// medir los plazos en pasos exactos. Con `TIME` la estática correría a la
// velocidad del bucle principal y la captura no sería reproducible.
//
// El tinte es cálido porque es **nuestra** señal la que se rompe: la regla de
// coherencia de `docs/13` dice que nada propio es cian. La imperfección —el piso
// de luminancia, las barras torcidas— también es nuestra.
shader_type canvas_item;
render_mode blend_mix, unshaded;

// Maestro: 0 apaga la estática por completo. El componente lo baja a 0 al
// terminar, de modo que un material olvidado encendido no pinta nada.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// Recorrido de la ráfaga, de 0 (recién cortada) a 1 (negro). Manda la caída.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Reloj propio del componente, en segundos.
uniform float clock = 0.0;

// Cuadros de ruido por segundo. Por debajo de ~20 el ruido se lee como parpadeo.
uniform float time_scale : hint_range(1.0, 120.0) = 34.0;

// Lado de la celda de ruido, en píxeles de pantalla. Con 1 el grano se pierde en
// la captura; con más de 6 se lee como mosaico y no como estática.
uniform float grain_px : hint_range(1.0, 16.0) = 3.0;

// Cuántas barras anchas entran en la altura de la pantalla.
uniform float bar_count : hint_range(0.0, 12.0) = 3.0;

// Tinte de la estática. Por defecto el ámbar del HUD (`UIPalette.HUD_TEXT`).
uniform vec3 tint : source_color = vec3(1.0, 0.816, 0.541);

// Alturas de pantalla por segundo que recorre la barra ancha.
const float BAR_SPEED = 0.8;

// Punto del recorrido en el que empieza la caída a negro.
const float BLACKOUT_START = 0.62;

// Piso de luminancia del ruido: sin él la pantalla titila entre negro y blanco
// puros y se lee como un error de dibujo, no como una señal.
const float LUMA_FLOOR = 0.18;

// Hash entero → [0,1). Sin texturas, sin bucles y sin derivadas: una decena de
// ALU por píxel, que es todo lo que se puede gastar en un rectángulo a pantalla
// completa.
float hash21(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	// Cuadro de ruido en curso. `floor` es lo que hace que el grano salte.
	float frame = floor(clock * time_scale);
	vec2 cell = floor(FRAGCOORD.xy / max(grain_px, 1.0));
	// El 1.618 desacopla las dos coordenadas del hash: con el mismo valor en las
	// dos, los cuadros consecutivos salen correlacionados y el ruido «respira».
	float noise = hash21(cell + vec2(frame, frame * 1.618));

	float wide = fract(SCREEN_UV.y * bar_count - clock * BAR_SPEED * bar_count);
	float thin = fract(SCREEN_UV.y * bar_count * 7.0 + clock * BAR_SPEED * 5.0);
	float roll = smoothstep(0.80, 1.0, wide) * 0.55 - smoothstep(0.92, 1.0, thin) * 0.45;

	float luma = clamp(LUMA_FLOOR + noise * (1.0 - LUMA_FLOOR) + roll, 0.0, 1.0);
	float black = smoothstep(BLACKOUT_START, 1.0, progress);

	COLOR = vec4(tint * luma * (1.0 - black), intensity);
}
