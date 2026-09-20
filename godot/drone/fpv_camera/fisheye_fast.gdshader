// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Ojo de pez FAST y FAST_WIDE (`docs/03` §5): compone uno o tres renders
// **rectilíneos** en una proyección **equidistante** de `hfov` grados.
//
// Geometría (pública, proyección equidistante de una lente de ojo de pez):
//   - el píxel de salida está a radio `r` del centro, medido en medias-anchuras de
//     pantalla, así que `r = 1` es el borde horizontal;
//   - ese radio corresponde al ángulo `θ = r · hfov/2` respecto del eje óptico
//     (equidistante: el radio es proporcional al ángulo, no a su tangente);
//   - con el azimut `φ` la dirección en espacio de cámara es
//     `d = (sin θ·cos φ, −sin θ·sin φ, −cos θ)` (eje óptico en −Z, +X a la derecha,
//     +Y arriba; el −y sale de que la pantalla crece hacia abajo).
//
// Es la inversa exacta de `FPVCamera.project_direction()`, que va de la dirección al
// píxel con la misma fórmula equidistante; por eso el HUD y la imagen coinciden
// (`docs/12` §3.1). `FPVCamera.coverage()` es el espejo en GDScript de `cover`.
//
// ## Cada cara, en coordenadas normalizadas
//
// Una cara rectilínea de medio campo `h` cubre `|n| ≤ 1`, con
// `n = (d·derecha, −d.y) / (d·eje · tan h)` y textura `uv = n·0.5 + 0.5`.
//
//   - **frontal** (16:9, `render_fov` = 120° horizontales): `eje = −Z`,
//     `derecha = +X`, y la componente vertical lleva `front_aspect` porque la
//     sub-cámara usa `KEEP_WIDTH`: `n = (d.x, −d.y·front_aspect) / (−d.z · tan(60°))`.
//   - **laterales** (cuadradas, `side_fov` = 100°, giradas `±side_yaw` = ±60°):
//     se elige la del signo de `d.x`; con `s = ±1`,
//     `eje = (s·sin 60°, 0, −cos 60°)` y `derecha = (cos 60°, 0, s·sin 60°)`.
//
// ## Por qué hay viñeta y no estiramiento (WP-24c)
//
// La versión anterior acotaba el muestreo con `clamp(uv, 0, 1)`: más allá de
// `render_fov/2` repetía el texel del borde. A `hfov` 150 el borde horizontal pide
// θ = 75° y la frontal sólo llega a 60°, así que los últimos **192 px de cada
// costado** a 1920 eran el mismo píxel repetido —el churretón que reportó el
// jugador—. Acá el peso `w` de cada cara cae a cero **antes** de salirse de su
// frustum, así que nunca se muestrea fuera de `[0, 1]`:
//
//   `w = (1 − smoothstep(1−fx, 1, |n.x|)) · (1 − smoothstep(1−fy, 1, |n.y|))`
//
// Los dos anchos de transición son distintos a propósito:
//   - `edge_fade` (0,10 → de 57,3° a 60°, unos 32 px a 1920) va en horizontal y en
//     las dos direcciones de las laterales: es a la vez la viñeta de FAST y el
//     fundido cruzado con la lateral en FAST_WIDE;
//   - `edge_fade_y` (0,02) va en el **vertical de la frontal**, donde no hay ninguna
//     otra cara que pueda tomar el relevo: arriba y abajo del centro la frontal es
//     lo único que existe, y un fundido ancho ahí oscurecería el borde superior e
//     inferior hasta el 38 % (medido). Con 0,02 la transición sigue midiendo entre
//     4 y 10 px, de sobra para que no se vea escalonada.
//
// ## Unión y prioridad (`cover`)
//
//   `cover = wf + (1 − wf)·ws`      (unión probabilística: 1 si **alguna** cara vale)
//   `rgb   = (frontal·wf + lateral·(1 − wf)·ws) / cover`, negro si `cover == 0`
//
// La frontal tiene prioridad —es la de más resolución— y la lateral sólo aparece
// donde la frontal se está acabando, con lo que el fundido cruzado ocurre en la
// banda `|n.x| ∈ [0,9, 1]` y no en todo el solape. Sin ese `/ cover` la banda de
// fundido saldría a media luz, que es un halo oscuro tan visible como la costura.
//
// Verificación numérica a `hfov` 150 y 16:9 (`tools/hud_projection_check` fila 13):
//   - borde horizontal θ 75°: la frontal pide `|n| = 2,155` (fuera), la lateral
//     queda en `n = (0,225, 0)` → `cover = 1`;
//   - esquina θ 86,05°, φ 29,36°: frontal `|n| = 7,29` (fuera), lateral
//     `n = (0,400, 0,521)` → `cover = 1`;
//   - peor punto del borde superior, φ 62°: frontal `n.y = 0,999` (justo en el
//     límite) y lateral `n = (−0,538, 0,861)` → `cover = 1`;
//   - centro del borde superior, φ 90°: la lateral **no** llega (`n = (−1,45, 1,52)`)
//     y la frontal vale `n.y = 0,930` → la cubre ella sola, y por eso `edge_fade_y`
//     tiene que ser chico.
// En FAST_WIDE la cobertura es 1,000 en **todo** el cuadro de 90° a 157° de `hfov`
// con aspectos ≥ 1,5; la viñeta aparece recién arriba de 157°.
//
// ## Supermuestreo
//
// Hacia el borde la frontal se **minifica**: 1,57 texels por píxel a `|n| = 0,6`,
// 2,59 a 0,9 y 3,02 a 1,0. Una `ViewportTexture` no tiene mipmaps (el hint
// `filter_linear_mipmap` no los crea), así que a partir de `SUPERSAMPLE_FROM` se
// toman cuatro muestras en rejilla rotada 4× sobre la huella real del píxel, que
// `dFdx`/`dFdy` dan gratis. Las laterales **magnifican** (≤ 1,0 texels por píxel a
// 720² sobre una salida de 1920) y no lo necesitan.
shader_type canvas_item;
render_mode unshaded;

// Render rectilíneo frontal, con la relación de aspecto de la pantalla.
uniform sampler2D front_texture : filter_linear, repeat_disable;

// Caras laterales cuadradas de FAST_WIDE. En FAST quedan sin asignar y sin usar.
uniform sampler2D side_right_texture : filter_linear, repeat_disable;
uniform sampler2D side_left_texture : filter_linear, repeat_disable;

// Campo horizontal del ojo de pez, en grados (`QuadSettings.fov`, 90–170).
uniform float hfov : hint_range(60.0, 180.0) = 150.0;

// Campo horizontal del render rectilíneo frontal, en grados (120 en `docs/03` §10).
uniform float render_fov : hint_range(30.0, 170.0) = 120.0;

// Relación ancho/alto del rectángulo de salida.
uniform float aspect = 1.7777778;

// Relación ancho/alto de la sub-viewport frontal. Coincide con `aspect` salvo por el
// redondeo a píxeles enteros del alto del preset.
uniform float front_aspect = 1.7777778;

// FAST_WIDE: `true` agrega las dos caras laterales.
uniform bool use_sides = false;

// Campo de cada cara lateral, en grados.
uniform float side_fov : hint_range(40.0, 170.0) = 100.0;

// Guiñada de cada cara lateral respecto del eje óptico, en grados.
uniform float side_yaw : hint_range(0.0, 90.0) = 60.0;

// Ancho de la transición a negro en horizontal y en las laterales, en unidades de
// `n` (0,10 ≈ de 57,3° a 60° en la frontal).
uniform float edge_fade : hint_range(0.001, 0.5) = 0.1;

// Ídem en el vertical de la frontal, donde ninguna lateral toma el relevo.
uniform float edge_fade_y : hint_range(0.001, 0.5) = 0.02;

// A partir de este `|n|` la frontal se minifica y se toman cuatro muestras.
const float SUPERSAMPLE_FROM = 0.6;

// Profundidad mínima para que una cara tenga imagen rectilínea: por detrás de su
// propio plano la tangente diverge y no hay nada que muestrear.
const float MIN_DEPTH = 1e-3;


// Peso de una cara en un eje: 1 bien adentro del frustum, 0 justo en el borde.
float edge_weight(float n, float fade) {
	return 1.0 - smoothstep(1.0 - fade, 1.0, abs(n));
}


// Cuatro muestras en rejilla rotada (RGSS 4×) sobre la huella del píxel de salida.
// Las derivadas llegan como parámetro porque `dFdx`/`dFdy` no se pueden evaluar
// dentro de una rama no uniforme.
vec3 sample_rgss(sampler2D tex, vec2 uv, vec2 dx, vec2 dy) {
	vec3 acc = texture(tex, uv + 0.125 * dx + 0.375 * dy).rgb;
	acc += texture(tex, uv + 0.375 * dx - 0.125 * dy).rgb;
	acc += texture(tex, uv - 0.125 * dx - 0.375 * dy).rgb;
	acc += texture(tex, uv - 0.375 * dx + 0.125 * dy).rgb;
	return acc * 0.25;
}


void fragment() {
	// Coordenadas en medias-anchuras: x ∈ [−1, 1] de borde a borde, y con la misma
	// escala que x para que el campo sea circular y no elíptico.
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x, p.y / aspect);
	float r = length(q);
	float theta = r * radians(hfov) * 0.5;
	vec2 dir = r > 1e-6 ? q / r : vec2(0.0);
	float sin_theta = sin(theta);
	vec3 d = vec3(sin_theta * dir.x, -sin_theta * dir.y, -cos(theta));

	// --- cara frontal ---------------------------------------------------------------
	float half_front = tan(radians(render_fov) * 0.5);
	float depth_front = -d.z;
	vec2 n_front = vec2(d.x, -d.y * front_aspect)
			/ (max(depth_front, MIN_DEPTH) * half_front);
	vec2 uv_front = n_front * 0.5 + vec2(0.5);

	// --- cara lateral del lado de `d.x` ----------------------------------------------
	float side = d.x >= 0.0 ? 1.0 : -1.0;
	float cos_yaw = cos(radians(side_yaw));
	float sin_yaw = sin(radians(side_yaw));
	vec3 axis = vec3(side * sin_yaw, 0.0, -cos_yaw);
	vec3 right = vec3(cos_yaw, 0.0, side * sin_yaw);
	float half_side = tan(radians(side_fov) * 0.5);
	float depth_side = dot(d, axis);
	vec2 n_side = vec2(dot(d, right), -d.y) / (max(depth_side, MIN_DEPTH) * half_side);
	vec2 uv_side = n_side * 0.5 + vec2(0.5);

	// Las derivadas se evalúan siempre, fuera de toda rama: en control de flujo no
	// uniforme `dFdx`/`dFdy` no están definidas.
	vec2 ddx = dFdx(uv_front);
	vec2 ddy = dFdy(uv_front);

	float weight_front = depth_front > MIN_DEPTH
			? edge_weight(n_front.x, edge_fade) * edge_weight(n_front.y, edge_fade_y)
			: 0.0;
	float weight_side = use_sides && depth_side > MIN_DEPTH
			? edge_weight(n_side.x, edge_fade) * edge_weight(n_side.y, edge_fade)
			: 0.0;

	// Unión: la frontal manda y la lateral sólo llena lo que a aquella le falta.
	float blend_side = (1.0 - weight_front) * weight_side;
	float cover = weight_front + blend_side;

	vec3 rgb = vec3(0.0);
	if (cover > 1e-5) {
		vec3 front = vec3(0.0);
		if (weight_front > 0.0) {
			front = max(abs(n_front.x), abs(n_front.y)) > SUPERSAMPLE_FROM
					? sample_rgss(front_texture, uv_front, ddx, ddy)
					: texture(front_texture, uv_front).rgb;
		}
		vec3 flank = vec3(0.0);
		if (blend_side > 0.0) {
			flank = side > 0.0
					? texture(side_right_texture, uv_side).rgb
					: texture(side_left_texture, uv_side).rgb;
		}
		rgb = (front * weight_front + flank * blend_side) / cover;
	}
	COLOR = vec4(rgb, 1.0);
}
