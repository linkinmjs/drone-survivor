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
//   3. se elige la cara cuyo eje domina en `|d|` —el mismo criterio de un mapa de
//      cubo— y se proyecta `d` con la matriz de esa cara.
//
// Con `hfov ≤ 180` nunca hace falta la cara trasera: `θ ≤ 90°` implica `d.z ≤ 0`. Con
// caras de 100° y repartos de ±45° quedan 5° de solape por borde, que es lo que evita
// una costura visible entre caras.
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

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x, p.y / aspect);
	float r = length(q);
	float theta = r * radians(hfov) * 0.5;
	vec3 rgb = vec3(0.0);
	if (theta < radians(89.5)) {
		vec2 direction = r > 1e-6 ? q / r : vec2(0.0, 0.0);
		// La pantalla crece hacia abajo y la cámara hacia arriba: de ahí el −y.
		vec3 d = vec3(sin(theta) * direction.x, -sin(theta) * direction.y, -cos(theta));
		vec3 ad = abs(d);
		// `face_direction` es `d` visto desde la cara elegida, o sea la rotación
		// inversa de la que lleva la sub-cámara.
		vec3 face_direction = d;
		int face = 0;
		if (ad.z >= ad.x && ad.z >= ad.y) {
			face = 0;
			face_direction = d;
		} else if (ad.x >= ad.y) {
			face = d.x > 0.0 ? 1 : 2;
			face_direction = d.x > 0.0 ? vec3(d.z, d.y, -d.x) : vec3(-d.z, d.y, d.x);
		} else {
			face = d.y > 0.0 ? 3 : 4;
			face_direction = d.y > 0.0 ? vec3(d.x, d.z, -d.y) : vec3(d.x, -d.z, d.y);
		}
		float depth = max(-face_direction.z, 1e-4);
		float half_tangent = tan(radians(face_fov) * 0.5);
		vec2 face_uv = vec2(face_direction.x, -face_direction.y)
				/ (depth * half_tangent) * 0.5 + vec2(0.5);
		face_uv = clamp(face_uv, vec2(0.0), vec2(1.0));
		if (face == 0) {
			rgb = texture(face_front, face_uv).rgb;
		} else if (face == 1) {
			rgb = texture(face_right, face_uv).rgb;
		} else if (face == 2) {
			rgb = texture(face_left, face_uv).rgb;
		} else if (face == 3) {
			rgb = texture(face_up, face_uv).rgb;
		} else {
			rgb = texture(face_down, face_uv).rgb;
		}
	}
	COLOR = vec4(rgb, 1.0);
}
