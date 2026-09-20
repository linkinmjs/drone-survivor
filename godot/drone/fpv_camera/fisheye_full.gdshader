// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Ojo de pez FULL (`docs/03` §5): compone cinco renders rectilíneos de `face_fov`
// grados —frente, izquierda, derecha, arriba y abajo— en una proyección
// **equidistante** de `hfov` grados, sin el estiramiento del modo FAST.
//
// Para cada píxel de salida:
//   1. `r` = radio en medias-anchuras de pantalla, `θ = r · hfov/2`, `φ` = azimut;
//   2. dirección en el espacio de la cámara `d = (sin θ·cos φ, sin θ·sin φ, −cos θ)`
//      (eje óptico en −Z, +X a la derecha, +Y arriba, como cualquier `Camera3D`);
//   3. se proyecta `d` sobre **las cinco** caras y se mezclan las que la contienen,
//      con peso decreciente hacia el borde de cada una.
//
// Con `hfov ≤ 180` nunca hace falta la cara trasera: `θ ≤ 90°` implica `d.z ≤ 0`. Con
// caras de 100° y repartos de ±45° quedan 5° de solape por borde.
//
// ## Qué cambió en WP-24c
//
// Antes se elegía **una** cara por eje dominante y se acotaba con
// `clamp(face_uv, 0, 1)`. Ese `clamp` era código muerto —con caras de 100° el eje
// dominante nunca pide más de `tan 45° / tan 50° = 0,839`— pero la conmutación seca
// dejaba una costura de un texel en cada uno de los cuatro bordes, justo donde el
// muestreo de las dos caras difiere más.
//
// Ahora cada cara `i` aporta con el peso
//
//   `wᵢ = (1 − smoothstep(1−fade, 1, |nᵢ.x|)) · (1 − smoothstep(1−fade, 1, |nᵢ.y|))`
//
// con `nᵢ = (dᵢ.x, −dᵢ.y) / (−dᵢ.z · tan(face_fov/2))` —la misma normalización que
// `fisheye_fast.gdshader`— y el color es `Σ wᵢ·caraᵢ / Σ wᵢ`, negro si `Σ wᵢ = 0`.
// Es una partición de la unidad: en el borde exacto entre dos caras las dos pesan
// igual, y a 5° hacia adentro sólo queda la dominante.
//
// `edge_fade` tiene que ser **mayor que `1 − tan 45°/tan(face_fov/2)` = 0,161** o el
// reparto tendría una meseta de 50/50 de cuatro grados de ancho —o sea, una banda
// borrosa en vez de una costura—. De ahí el 0,20 por defecto.
//
// Fuera de las cinco caras el resultado es negro y no el texel del borde repetido,
// que es la misma regla de honestidad que `fisheye_fast.gdshader`. A `hfov ≤ 180` eso
// no llega a pasar nunca: las cinco caras cubren el hemisferio entero.
shader_type canvas_item;
render_mode unshaded;

// Las cinco sub-viewports, cuadradas y con el mismo `face_fov`.
uniform sampler2D face_front : filter_linear, repeat_disable;
uniform sampler2D face_left : filter_linear, repeat_disable;
uniform sampler2D face_right : filter_linear, repeat_disable;
uniform sampler2D face_up : filter_linear, repeat_disable;
uniform sampler2D face_down : filter_linear, repeat_disable;

// Campo horizontal del ojo de pez, en grados (`QuadSettings.fov`, 90–170).
uniform float hfov : hint_range(60.0, 180.0) = 150.0;

// Campo de cada cara, en grados (100 en `docs/03` §10).
uniform float face_fov : hint_range(60.0, 170.0) = 100.0;

// Relación ancho/alto del rectángulo de salida.
uniform float aspect = 1.7777778;

// Ancho de la banda de mezcla entre caras, en unidades de `n`. Ver la cabecera:
// por debajo de 0,161 el reparto tiene meseta.
uniform float edge_fade : hint_range(0.17, 0.5) = 0.2;

// Profundidad mínima para que una cara tenga imagen rectilínea.
const float MIN_DEPTH = 1e-3;


// `d` visto desde una cara, ya en coordenadas normalizadas: `|n| ≤ 1` dentro.
vec2 face_normalized(vec3 face_direction, float half_tangent) {
	float depth = max(-face_direction.z, MIN_DEPTH);
	return vec2(face_direction.x, -face_direction.y) / (depth * half_tangent);
}


// Peso de la cara: 1 bien adentro, 0 justo en el borde del frustum.
float face_weight(vec3 face_direction, float half_tangent, float fade) {
	if (-face_direction.z <= MIN_DEPTH) {
		return 0.0;
	}
	vec2 n = abs(face_normalized(face_direction, half_tangent));
	return (1.0 - smoothstep(1.0 - fade, 1.0, n.x))
			* (1.0 - smoothstep(1.0 - fade, 1.0, n.y));
}


// Acumula una cara en `sum`/`total` si aporta algo.
void accumulate(sampler2D tex, vec3 face_direction, float half_tangent, float fade,
		inout vec3 sum, inout float total) {
	float w = face_weight(face_direction, half_tangent, fade);
	if (w <= 0.0) {
		return;
	}
	vec2 uv = face_normalized(face_direction, half_tangent) * 0.5 + vec2(0.5);
	sum += texture(tex, uv).rgb * w;
	total += w;
}


void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x, p.y / aspect);
	float r = length(q);
	float theta = r * radians(hfov) * 0.5;
	vec2 dir = r > 1e-6 ? q / r : vec2(0.0);
	// La pantalla crece hacia abajo y la cámara hacia arriba: de ahí el −y.
	vec3 d = vec3(sin(theta) * dir.x, -sin(theta) * dir.y, -cos(theta));
	float half_tangent = tan(radians(face_fov) * 0.5);

	// Cada `face_direction` es `d` visto desde esa cara, o sea la rotación inversa de
	// la que lleva su sub-cámara (`FPVCamera._face_basis`).
	vec3 sum = vec3(0.0);
	float total = 0.0;
	accumulate(face_front, d, half_tangent, edge_fade, sum, total);
	accumulate(face_right, vec3(d.z, d.y, -d.x), half_tangent, edge_fade, sum, total);
	accumulate(face_left, vec3(-d.z, d.y, d.x), half_tangent, edge_fade, sum, total);
	accumulate(face_up, vec3(d.x, d.z, -d.y), half_tangent, edge_fade, sum, total);
	accumulate(face_down, vec3(d.x, -d.z, d.y), half_tangent, edge_fade, sum, total);

	COLOR = vec4(total > 1e-5 ? sum / total : vec3(0.0), 1.0);
}
