// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Terreno del pueblo (`docs/10` §4.4, plan P2c §2, WP-T2).
//
// Mezcla cuatro colores base con el peso de capa que el horneado dejó en el
// COLOR de cada vértice —pasto, tierra, roca y arena de lecho— y les añade un
// detalle triplanar procedural para que a cuatro metros de la cámara la malla
// no se lea como un degradado liso. No hay ni una textura: el detalle es ruido
// de valor por hash, que cuesta cuatro muestras y no entra en el presupuesto de
// VRAM de `docs/10` §2.3.
//
// El tono general es el de `assets/city/materials/field.tres` —el plano lejano
// que sigue cubriendo el campo fuera de ±256 m— para que el empalme entre el
// relieve y el plano no se vea.

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Los cuatro colores base, en el orden en que el horneado guarda los pesos:
// COLOR.r pasto, COLOR.g tierra, COLOR.b roca, COLOR.a arena de lecho.
// El pasto queda donde estaba: es el tono medio del degradado de
// `assets/city/materials/field.tres` —el campo de P2b— y es lo que hace que el
// anillo lejano y el relieve sean el mismo prado.
//
// Los otros tres subieron en WP-T5. Estaban **todos por debajo del pasto** y
// eso invierte la lectura: una pendiente pelada se veía como una mancha
// oscura, el lecho del arroyo como un pozo negro y el patio de cada manzana
// —que el horneado pinta de tierra— como un agujero. Con la tierra y la arena
// por encima del pasto, la pendiente se lee seca, el cauce se lee arenoso y
// el relieve se sigue con el ojo desde el dron.
//
// WP-D3 vuelve a subir **sólo la tierra**, de (0.196, 0.152, 0.104) a
// (0.268, 0.214, 0.146): un 37 % más clara, mismo tono. El pasto no se toca
// porque es el que empalma con `field.tres` en el anillo lejano y moverlo
// mostraría la costura a 256 m. Lo que se busca es el **patio**: con
// `CIVIL_DIRT` en 0,42 el interior de cada manzana pasa a ser 42 % tierra, y
// entre las dos palancas la luminancia del patio sube sin que el campo abierto
// cambie un punto.
uniform vec3 grass_color : source_color = vec3(0.152, 0.158, 0.104);
uniform vec3 dirt_color : source_color = vec3(0.268, 0.214, 0.146);
uniform vec3 rock_color : source_color = vec3(0.186, 0.184, 0.176);
uniform vec3 sand_color : source_color = vec3(0.285, 0.252, 0.182);

// Detalle procedural: dos escalas, una de mancha y otra de grano.
uniform float patch_scale : hint_range(0.005, 0.2) = 0.035;
uniform float grain_scale : hint_range(0.05, 2.0) = 0.45;
uniform float patch_strength : hint_range(0.0, 1.0) = 0.30;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.13;

uniform float terrain_roughness : hint_range(0.0, 1.0) = 0.99;
uniform float terrain_specular : hint_range(0.0, 1.0) = 0.08;

varying vec3 world_position;
varying vec3 world_normal;

// Hash entero barato: una multiplicación y dos mezclas por eje. Es
// determinista y no necesita textura.
float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Ruido de valor con interpolación suave. Cuatro hashes por muestra.
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Ruido triplanar: tres muestras mezcladas por la normal del mundo. En el
// llano —que es casi todo el pueblo— domina la muestra XZ; en los taludes del
// arroyo y en las lomas empinadas entran las otras dos, que es donde una
// muestra plana se estiraría.
float triplanar_noise(vec3 p, vec3 n, float scale) {
	vec3 blend = abs(n);
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	float x = value_noise(p.zy * scale);
	float y = value_noise(p.xz * scale);
	float z = value_noise(p.xy * scale);
	return x * blend.x + y * blend.y + z * blend.z;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Los pesos salen del horneado ya normalizados, pero una malla editada a
	// mano o un vértice mal pintado no deben apagar el terreno: se renormaliza.
	vec4 weights = max(COLOR, vec4(0.0));
	float total = max(weights.r + weights.g + weights.b + weights.a, 0.0001);
	weights /= total;

	vec3 base = grass_color * weights.r
			+ dirt_color * weights.g
			+ rock_color * weights.b
			+ sand_color * weights.a;

	// Mancha grande triplanar y grano fino plano: la mancha rompe el color por
	// zonas y el grano da textura al pisar. El grano se toma sólo en XZ porque
	// a la distancia a la que se ve es plano de todos modos.
	float patch = triplanar_noise(world_position, world_normal, patch_scale);
	float grain = value_noise(world_position.xz * grain_scale);
	float detail = 1.0 + (patch - 0.5) * 2.0 * patch_strength
			+ (grain - 0.5) * 2.0 * grain_strength;

	ALBEDO = clamp(base * detail, vec3(0.0), vec3(1.0));
	// La roca es un poco menos áspera que el pasto y la arena un poco más:
	// es lo que separa las tres capas cuando el sol rasante del anochecer les
	// pega de costado.
	ROUGHNESS = clamp(terrain_roughness - weights.b * 0.12 + weights.a * 0.01, 0.0, 1.0);
	SPECULAR = terrain_specular;
	METALLIC = 0.0;
}
