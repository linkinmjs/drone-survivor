// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Overlay de la señal FPV en preset LOW: **solo viñeta** (`docs/13` §3.4, fila
// `fpv_overlay`).
//
// ## Por qué es un shader aparte y no un uniform de `fpv_overlay.gdshader`
//
// Porque lo caro del overlay completo no son sus tres lecturas ni sus ALU: es que
// `uniform sampler2D screen_tex : hint_screen_texture` obliga al renderizador a
// **copiar el backbuffer** antes de dibujar el rectángulo, y esa copia se paga aunque
// el shader decida no usar la textura. Un `if (full)` dentro del shader completo
// dejaría a LOW pagando una copia de pantalla entera a 1080p para pintar una viñeta.
//
// Acá no hay `screen_tex`: el rectángulo es negro y lo único que varía es el alfa, de
// modo que la viñeta sale del propio mezclado (`blend_mix`) y no hay copia ninguna.
//
// Conserva el latido a 1,5 Hz con `damage` —sigue siendo viñeta y nada más— porque es
// la única forma que le queda a LOW de contar que el casco está mal; el grano, las
// scanlines, la aberración y todo el EMP se apagan.
shader_type canvas_item;
render_mode blend_mix, unshaded;

// Oscurecimiento máximo en el borde. El mismo valor que el overlay completo.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

// Daño del casco, `1 − Events.hull_changed(ratio)`. Solo alimenta el latido.
uniform float damage : hint_range(0.0, 1.0) = 0.0;

// Reloj propio, en segundos. Lo escribe `FPVOverlay.tick()`.
uniform float time = 0.0;

const float PULSE_HZ = 1.5;
const float PULSE_DEPTH = 0.35;
const float VIGNETTE_INNER = 0.55;
const float VIGNETTE_OUTER = 1.45;

void fragment() {
	// 1,0 en el borde horizontal; 1,414 en las esquinas. Idéntico al overlay completo,
	// para que cambiar de preset no mueva la geometría de la viñeta.
	float radius = length(UV - vec2(0.5)) * 2.0;
	float pulse = 1.0 + damage * PULSE_DEPTH * sin(time * PULSE_HZ * TAU);
	float vignette = smoothstep(VIGNETTE_INNER, VIGNETTE_OUTER, radius);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(vignette_strength * vignette * pulse, 0.0, 1.0));
}
