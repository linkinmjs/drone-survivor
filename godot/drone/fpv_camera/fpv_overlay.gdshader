// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Overlay de la señal FPV (`docs/13` §7; `docs/narrativa` §4).
//
// «Lo que ve el jugador es exactamente lo que ve el dron: una señal de video con
// viñeta, ruido y color que se corre en los bordes.» Este shader es esa señal. Vive
// en un `ColorRect` de pantalla completa dentro de un `CanvasLayer` en la capa **−1**:
// encima del compuesto del ojo de pez (capa −2) y **debajo** del `FlightHUD` (capa 0),
// que tiene que leerse nítido en todos los casos.
//
// ## Tres estados, un solo pase
//
// 1. **Base** (`damage = 0`, `emp = 0`): viñeta radial, scanlines finas y grano. Está
//    siempre puesta y su trabajo es no notarse: vende que hay un enlace de video y no
//    una cámara de juego. Los valores de `docs/13` §9 —viñeta 0,35, ruido 0,035,
//    scanlines 0,06 a 540 líneas, aberración 1,2 px— son deliberadamente tímidos.
// 2. **`damage`** (= `1 − Events.hull_changed`): multiplica el grano hasta ×4, sube la
//    aberración a 4 px, tiñe **los bordes** hacia `UIPalette.DANGER` y hace latir la
//    viñeta a 1,5 Hz. El tinte va contra la luminancia del píxel y acotado a la corona
//    exterior justamente para que se lea como **señal enferma** y no como un filtro
//    rojo encima del juego: el centro del cuadro, donde está el retículo, no se tiñe.
// 3. **`emp`** (= `1 − t/glitch_seconds` de `EnergySystem.emp_hit`): desplaza bloques
//    de `floor(UV.y · 24)` filas con un corrimiento pseudoaleatorio por bloque,
//    desatura hasta 0,2 y pasa una barra brillante de arriba abajo cada 0,6 s.
//
// ## El grano es ruido de ganancia, no ruido aditivo plano
//
// `docs/13` §7 dice «ruido de grano» y nada más. Se implementa **multiplicativo y
// pesado a los medios tonos** (`col *= 1 + ruido · 4·L·(1−L)`), que es el ruido que mete
// el amplificador de un enlace analógico después del control automático de ganancia y
// la campana clásica del grano de película, y no un `+= ruido` plano. Tres razones, y
// las tres son de imagen antes que de física:
//
//  - **Un aditivo plano ensucia los negros.** Con `noise_amount` 0,035 y el recorte en
//    0, un píxel negro sube a 0,0175 de media: la viñeta honesta del ojo de pez FAST
//    —los 28 % del cuadro que WP-24c peleó para que fueran negro de verdad y no
//    churretón— se llenaría de nieve, y el negro de las cajas del HUD dejaría de serlo.
//  - **Y rompe lo que se mide sobre la imagen.** La fila [11] de `hud_projection_check`
//    compara el horizonte dibujado contra la transición cielo/suelo de una captura con
//    todo escondido salvo un plano negro; en esa escena el contraste total entre el
//    cielo del atardecer y el plano es **0,040**. Un grano de ±0,035 ahí no es ruido
//    sobre la medición: **es** la medición. Medido: con grano plano las cinco columnas
//    daban `NAN` o errores de 100 px.
//  - **Y rompe la comparación A/B de la fila [14]**, que mide |Δluminancia| píxel a
//    píxel entre dos capturas de la misma pose en modos distintos. Cualquier ruido
//    temporal aparece ahí como diferencia; con el grano proporcional la diferencia
//    media cae dentro de la tolerancia porque el ruido es una fracción de la señal y no
//    un piso constante.
//
// Sobre medios tonos el grano se sigue viendo —a luminancia 0,5 la amplitud efectiva es
// la mitad de `noise_amount`—, que es donde tiene que verse; y con `damage` a 1 el ×4 lo
// lleva a ±7 % de la señal, que es un enlace claramente enfermo.
//
// ## Por qué `time` y no `TIME`
//
// Igual que `hud/combat/static.gdshader`: el reloj lo escribe el script con el delta
// del motor, así que un check puede congelarlo y avanzarlo a mano y las capturas son
// reproducibles. Con `TIME` el grano correría a la velocidad del bucle principal.
//
// ## Coste
//
// **Tres** lecturas de `screen_tex` —R, G y B de la aberración— y una decena de ALU.
// No hay bucles, no hay derivadas y las dos ramas (`emp`, `damage`) son sobre
// uniforms, así que el warp entero toma la misma. El gasto fijo real no es el shader
// sino la copia de backbuffer que `hint_screen_texture` obliga a hacer: por eso en
// preset LOW se usa `fpv_overlay_low.gdshader`, que no lee la pantalla.
//
// ### `filter_linear` y no `filter_linear_mipmap`
//
// `docs/13` §7 escribe `filter_linear_mipmap`, y **cuesta el triple**. Pedir mipmaps de
// una textura de pantalla no cambia el filtrado que se usa —acá nunca se muestrea con
// LOD explícito, y las tres lecturas están a 1,2–4 px una de otra, o sea LOD 0— pero
// obliga al renderizador a generar la cadena de mips de la copia de backbuffer entera
// en cada cuadro. Medido a 1080p en una RTX 3060 con `tools/overlay_shots.tscn`, sobre
// la viewport raíz (que con ojo de pez solo compone canvas):
//
// | Estado | `filter_linear_mipmap` | `filter_linear` |
// |---|---|---|
// | base | +0,242 ms | **+0,078 ms** |
// | daño 1,0 | +0,249 ms | **+0,084 ms** |
// | EMP 1,0 | +0,267 ms | **+0,102 ms** |
//
// Con mipmaps el estado de EMP **se pasaba** del presupuesto de 0,25 ms de §7; sin
// ellos sobra un factor de dos y la imagen es exactamente la misma. Queda anotado como
// discrepancia con el documento.
//
// Nada acá es cian (`docs/13` §2.1): el tinte de daño es `DANGER` y la barra del EMP
// es blanca-ámbar tenue. El cian es del enemigo.
shader_type canvas_item;
render_mode blend_mix, unshaded;

// La pantalla ya compuesta: con ojo de pez activo, el `ColorRect` de la capa −2.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Daño del casco, `1 − Events.hull_changed(ratio)`.
uniform float damage : hint_range(0.0, 1.0) = 0.0;

// Intensidad del EMP, de 1 a 0. En fase con `HUDGlitchLayer.emp_strength`.
uniform float emp : hint_range(0.0, 1.0) = 0.0;

// Oscurecimiento máximo de la viñeta en el borde.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

// Amplitud del grano a daño 0, en unidades de color.
uniform float noise_amount : hint_range(0.0, 0.3) = 0.035;

// Oscurecimiento máximo de una scanline.
uniform float scanline_amount : hint_range(0.0, 0.3) = 0.06;

// Scanlines que entran en la **altura de la pantalla**: van sobre `UV.y`, así que el
// grosor aparente no depende de la resolución de render.
uniform float scanline_count = 540.0;

// Separación de R y B en el borde horizontal, en píxeles reales.
uniform float aberration_px = 1.2;

// Reloj propio, en segundos. Lo escribe `FPVOverlay.tick()`.
uniform float time = 0.0;

// `UIPalette.DANGER`. Lo pasa el script: el shader no conoce la paleta.
uniform vec3 danger_color : source_color = vec3(1.0, 0.302, 0.302);

// Semilla del sorteo de bloques del EMP. Dos pulsos seguidos rompen distinto.
uniform float emp_seed = 0.0;

// --- Constantes de identidad (`docs/13` §7) --------------------------------------------------

// Aberración a daño pleno, en píxeles.
const float DAMAGE_ABERRATION_PX = 4.0;

// Multiplicador del grano a daño pleno.
const float DAMAGE_NOISE_GAIN = 4.0;

// Latido de la viñeta con daño.
const float PULSE_HZ = 1.5;
const float PULSE_DEPTH = 0.35;

// Radio normalizado (1,0 en el borde horizontal, 1,414 en las esquinas) donde la
// viñeta empieza y donde satura.
const float VIGNETTE_INNER = 0.55;
const float VIGNETTE_OUTER = 1.45;

// Corona en la que el daño tiñe, y cuánto tiñe a daño pleno.
const float TINT_INNER = 0.60;
const float TINT_OUTER = 1.35;
const float TINT_MAX = 0.55;

// Piso del tinte: sin él, un borde negro se quedaría negro y el daño no se vería.
const float TINT_FLOOR = 0.30;

// Cuadros de grano por segundo y lado de la celda en píxeles de pantalla. Los mismos
// que `static.gdshader`, para que los dos efectos hablen el mismo idioma visual: con
// celda de 1 px el grano se pierde en la captura y a la vez mete un gradiente nuevo
// entre cada par de píxeles vecinos, que es lo que confunde a cualquier detector de
// bordes que mire la imagen (la fila [11] de `hud_projection_check`).
const float GRAIN_HZ = 24.0;
const float GRAIN_PX = 3.0;

// Bloques del EMP: las filas de `docs/13` §7.
const float EMP_BLOCKS = 24.0;

// Resorteo de los bloques por segundo.
const float EMP_BLOCK_HZ = 18.0;

// Corrimiento horizontal máximo de un bloque, en unidades de UV.
const float EMP_SHIFT = 0.055;

// Umbral del sorteo que decide si un bloque se mueve. Con 0,45 se mueve poco más de
// la mitad: un desgarro, no una licuadora.
const float EMP_BLOCK_GATE = 0.45;

// Saturación que queda a EMP pleno.
const float EMP_SATURATION = 0.2;

// Segundos que tarda la barra en recorrer la pantalla, y su medio ancho en UV.
const float EMP_BAR_SECONDS = 0.6;
const float EMP_BAR_WIDTH = 0.035;

// Blanco-ámbar tenue: la barra es de **nuestra** señal rompiéndose.
const vec3 EMP_BAR_COLOR = vec3(1.0, 0.94, 0.82);
const float EMP_BAR_GAIN = 0.55;

// Pesos de luminancia Rec. 709.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Hash entero → [0,1), el mismo de `static.gdshader`: sin texturas, sin bucles y sin
// derivadas.
float hash21(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	// El `ColorRect` es de pantalla completa dentro de un `CanvasLayer` sin
	// transformada, así que `UV` y `SCREEN_UV` coinciden. Se usa `UV` para las formas
	// —es lo que escribe `docs/13` §7— y `SCREEN_UV` para leer, que es lo único que
	// seguiría valiendo si alguna vez el rectángulo dejara de cubrir la pantalla.
	vec2 centred = UV - vec2(0.5);
	float centred_len = length(centred);
	// 1,0 en el borde horizontal; 1,414 en las esquinas.
	float radius = centred_len * 2.0;

	// --- EMP: bloques desplazados y barra ---------------------------------------------------
	vec2 read_uv = SCREEN_UV;
	float bar = 0.0;
	if (emp > 0.0) {
		float block = floor(UV.y * EMP_BLOCKS);
		float step_index = floor(time * EMP_BLOCK_HZ);
		float pick = hash21(vec2(block + emp_seed, step_index));
		float gate = step(EMP_BLOCK_GATE,
				hash21(vec2(block + emp_seed + 31.0, step_index * 1.618)));
		read_uv.x += (pick * 2.0 - 1.0) * EMP_SHIFT * emp * gate;
		float bar_y = fract(time / EMP_BAR_SECONDS);
		bar = smoothstep(EMP_BAR_WIDTH, 0.0, abs(UV.y - bar_y)) * emp;
	}
	read_uv = clamp(read_uv, vec2(0.0), vec2(1.0));

	// --- Aberración cromática radial (tres lecturas, ni una más) -----------------------------
	float aberration = mix(aberration_px, DAMAGE_ABERRATION_PX, damage);
	vec2 unit = centred / max(centred_len, 0.0001);
	vec2 offset = unit * radius * aberration * SCREEN_PIXEL_SIZE;
	vec3 col;
	col.g = texture(screen_tex, read_uv).g;
	col.r = texture(screen_tex, clamp(read_uv + offset, vec2(0.0), vec2(1.0))).r;
	col.b = texture(screen_tex, clamp(read_uv - offset, vec2(0.0), vec2(1.0))).b;

	// --- EMP: desaturación y barra -----------------------------------------------------------
	if (emp > 0.0) {
		col = mix(col, vec3(dot(col, LUMA)), (1.0 - EMP_SATURATION) * emp);
		col += EMP_BAR_COLOR * bar * EMP_BAR_GAIN;
	}

	// --- Grano ------------------------------------------------------------------------------
	// **Multiplicativo**, no aditivo: es ruido de ganancia, el que mete el amplificador
	// del enlace, y por eso escala con la señal y deja el negro en negro. Ver la nota
	// de arriba.
	float grain_step = floor(time * GRAIN_HZ);
	vec2 cell = floor(FRAGCOORD.xy / GRAIN_PX);
	float noise = hash21(cell + vec2(grain_step, grain_step * 1.618));
	float grain = noise_amount * (1.0 + (DAMAGE_NOISE_GAIN - 1.0) * damage);
	float luma_now = clamp(dot(col, LUMA), 0.0, 1.0);
	// Peso parabólico: el grano vive en los medios tonos, se apaga en el negro y en el
	// cielo quemado. Es la campana del grano de película y de cualquier sensor con AGC.
	float weight = clamp(4.0 * luma_now * (1.0 - luma_now), 0.0, 1.0);
	col *= 1.0 + (noise - 0.5) * 2.0 * grain * weight;

	// --- Scanlines --------------------------------------------------------------------------
	float scan = 0.5 + 0.5 * cos(UV.y * scanline_count * TAU);
	col *= 1.0 - scanline_amount * scan;

	// --- Viñeta con latido ------------------------------------------------------------------
	float pulse = 1.0 + damage * PULSE_DEPTH * sin(time * PULSE_HZ * TAU);
	float vignette = smoothstep(VIGNETTE_INNER, VIGNETTE_OUTER, radius);
	col *= 1.0 - clamp(vignette_strength * vignette * pulse, 0.0, 1.0);

	// --- Tinte de daño en los bordes ---------------------------------------------------------
	if (damage > 0.0) {
		float edge = smoothstep(TINT_INNER, TINT_OUTER, radius);
		float amount = damage * edge * TINT_MAX;
		float luma = dot(col, LUMA);
		col = mix(col, danger_color * (TINT_FLOOR + (1.0 - TINT_FLOOR) * luma), amount);
	}

	// Alfa 1: el overlay **reemplaza** el píxel del compuesto, no se mezcla con él. Lo
	// que sigue en la capa 0 —el `FlightHUD`— se dibuja después y encima.
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
