// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Etapa DAMAGED de un edificio (`docs/10` §3.2 y riesgo 4).
//
// El pack FreeSample no trae variantes dañadas y autorar trece mallas rotas no
// entra en el presupuesto de WP-20, así que el boquete se hace **en el mismo
// mesh**: un ruido triplanar en espacio de mundo recorta fragmentos con
// ALPHA_SCISSOR, tizna de hollín el borde del corte y deja los emisivos
// apagados —este shader no escribe EMISSION, así que las ventanas encendidas de
// `StandardMaterial3D` desaparecen solas al ponerlo como `material_override`.
//
// El ruido es triplanar y en espacio de mundo a propósito: así dos edificios
// vecinos de la misma pieza no se rompen con el mismo patrón, y el corte sigue
// las caras del vóxel en vez de la UV del atlas, que está empaquetada por cara.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

// Difusa de la familia de la pieza (`assets/city/textures/`).
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

// 0 = intacto, 1 = deshecho. `Building` lo sube al entrar en DAMAGED.
uniform float damage_amount : hint_range(0.0, 1.0) = 0.34;

// Metros por celda de ruido. 10 m deja boquetes de dos o tres pisos; con celdas
// más chicas el edificio se lee despedazado en vez de dañado.
uniform float noise_scale : hint_range(0.5, 40.0) = 10.0;

// Hollín del borde del boquete.
uniform vec3 soot_color : source_color = vec3(0.16, 0.14, 0.13);

// Ancho del tiznado alrededor del corte, en unidades de ruido. Estrecho a
// propósito: con un tiznado ancho el edificio entero se lee negro desde el aire
// y deja de distinguirse de una silueta en contraluz.
uniform float soot_width : hint_range(0.0, 1.0) = 0.12;

// Cuánto del albedo reemplaza el hollín en el borde del corte.
uniform float soot_strength : hint_range(0.0, 1.0) = 0.7;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

varying vec3 v_world;

// Hash entero → [0,1). Determinista y sin texturas.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Ruido de valor trilineal.
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
			mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
			f.z);
}

// Dos octavas bastan: la malla es vóxel y un tercer nivel no se distingue.
float fbm(vec3 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.17 + 11.3) * 0.35;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(v_world / max(noise_scale, 0.001));
	// El daño sube el umbral: con 0 no se recorta nada, con 1 se va casi todo.
	float cut = damage_amount * 0.62;
	ALPHA = n;
	ALPHA_SCISSOR_THRESHOLD = cut;

	vec4 albedo = texture(albedo_texture, UV);
	// Hollín concentrado en el borde del corte, que es donde n roza el umbral.
	float soot = 1.0 - smoothstep(cut, cut + max(soot_width, 0.001), n);
	ALBEDO = mix(albedo.rgb * 0.88, soot_color, soot * soot_strength);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
