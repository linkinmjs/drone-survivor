// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Ojo de pez FAST (`docs/03` §5): remapea un render **rectilíneo** de `render_fov`
// grados a una proyección **equidistante** de `hfov` grados.
//
// Geometría (pública, proyección equidistante de una lente de ojo de pez):
//   - el píxel de salida está a radio `r` del centro, medido en medias-anchuras de
//     pantalla, así que `r = 1` es el borde horizontal;
//   - ese radio corresponde al ángulo `θ = r · hfov/2` respecto del eje óptico
//     (equidistante: el radio es proporcional al ángulo, no a su tangente);
//   - en el render rectilíneo ese mismo ángulo cae a `r' = f · tan θ` con la
//     distancia focal `f = 1 / tan(render_fov/2)`, también en medias-anchuras.
//
// Es la inversa exacta de `FPVCamera.project_direction()` en modo FAST, que va de la
// dirección al píxel; por eso el HUD y la imagen coinciden (`docs/12` §3.1).
//
// Más allá de `render_fov/2` el render fuente ya no tiene información: el muestreo se
// acota al borde, que es el «estiramiento en los bordes» que describe `docs/03` §5.
shader_type canvas_item;
render_mode unshaded;

// Render rectilíneo de la sub-viewport.
uniform sampler2D source_texture : filter_linear, repeat_disable;

// Campo horizontal del ojo de pez, en grados (`QuadSettings.fov`, 90–170).
uniform float hfov : hint_range(60.0, 180.0) = 150.0;

// Campo horizontal del render rectilíneo, en grados (120 en `docs/03` §10).
uniform float render_fov : hint_range(30.0, 170.0) = 120.0;

// Relación ancho/alto del rectángulo de salida.
uniform float aspect = 1.7777778;

void fragment() {
	// Coordenadas en medias-anchuras: x ∈ [−1, 1] de borde a borde, y con la misma
	// escala que x para que el campo sea circular y no elíptico.
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x, p.y / aspect);
	float r = length(q);
	float theta = r * radians(hfov) * 0.5;
	vec3 rgb = vec3(0.0);
	// Un ángulo de 90° o más no tiene imagen rectilínea (la tangente diverge).
	if (theta < radians(89.0)) {
		float source_radius = tan(theta) / tan(radians(render_fov) * 0.5);
		vec2 direction = r > 1e-6 ? q / r : vec2(0.0);
		vec2 source_q = direction * source_radius;
		vec2 source_uv = vec2(source_q.x, source_q.y * aspect) * 0.5 + vec2(0.5);
		rgb = texture(source_texture, clamp(source_uv, vec2(0.0), vec2(1.0))).rgb;
	}
	COLOR = vec4(rgb, 1.0);
}
