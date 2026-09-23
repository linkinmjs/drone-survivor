// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Agua del arroyo del pueblo (`docs/17` §4, WP-D3, defecto 5).
//
// Hasta WP-D2 el cauce era tierra arenosa: el relieve tallaba el canal y el
// puente cruzaba un pozo seco. Esta es la lámina de agua que lo llena, y es el
// **único** sitio del pueblo con transparencia (`docs/13` §4: sin `alpha` salvo
// el agua).
//
// Lo que hace y lo que deliberadamente no hace:
//
// - **Color base verde-azulado oscuro**, más oscuro que el cielo del anochecer:
//   un arroyo de campo con fondo de barro no es una pileta.
// - **Fresnel suave hacia el cielo**: mirando de canto —que es como se ve desde
//   la ruta y desde el puente— la lámina se aclara con el color del horizonte, y
//   eso es lo que la hace leerse como agua y no como una chapa pintada.
// - **Dos senos cruzados** desplazan la normal. Cuesta dos `sin` por fragmento y
//   no necesita ni una textura, que es lo que pide el presupuesto de VRAM de
//   `docs/10` §2.3.
// - **No hay reflexión planar ni refracción de pantalla**: las dos cuestan un
//   pase de render entero por 300 m² de agua que el jugador cruza en tres
//   segundos. El reflejo lo da el `ReflectionProbe`/SDFGI del nivel a través de
//   la rugosidad baja, que es suficiente a esta escala.
//
// El material lo escribe `tools/build_town.gd` (`_ensure_creek_material`) y la
// cinta la levanta `CityGrid._build_creek_water()`.

shader_type spatial;
// `cull_back` y no `cull_disabled`: la lámina se ve siempre desde arriba y
// dibujar las dos caras duplicaría el relleno de una superficie transparente,
// que es lo caro de esto. `depth_prepass_alpha` deja que el agua se ordene
// contra sí misma sin cortar el fondo.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley,
		specular_schlick_ggx;

// Verde azulado de agua quieta con fondo de barro.
uniform vec3 water_color : source_color = vec3(0.043, 0.078, 0.082);

// Con qué color se aclara el borde de fresnel: el del cielo del anochecer de
// `docs/13` §3.1, apagado, para que el agua no se vuelva un espejo celeste.
uniform vec3 sky_tint : source_color = vec3(0.180, 0.235, 0.330);

// Cuán rápido se abre el fresnel. 3.0 es el exponente de Schlick de toda la
// vida: a 90° de la normal domina el cielo, a plomo domina el agua.
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.55;

uniform float water_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.85;

// Ondulación: dos trenes de olas cruzados. `wave_scale` es el número de crestas
// por metro y `wave_speed` los metros por segundo a los que corren.
uniform float wave_scale : hint_range(0.05, 4.0) = 0.65;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.06;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Dos senos con períodos y rumbos distintos. El gradiente analítico de cada
	// uno es su coseno, así que la normal sale sin muestrear nada.
	float t = TIME * wave_speed;
	float a = world_position.x * wave_scale + world_position.z * wave_scale * 0.6 + t;
	float b = world_position.z * wave_scale * 1.37 - world_position.x * wave_scale * 0.4
			- t * 0.83;
	vec3 bump = vec3(
			cos(a) * wave_scale + cos(b) * wave_scale * -0.4,
			0.0,
			cos(a) * wave_scale * 0.6 + cos(b) * wave_scale * 1.37) * wave_amplitude;
	// La normal se escribe en espacio de **mundo** y se pasa a vista: la cinta
	// del arroyo no tiene tangentes útiles (es una cinta con miter) y una normal
	// de tangente saldría torcida en cada quiebre.
	vec3 normal_world = normalize(vec3(0.0, 1.0, 0.0) + bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power) * fresnel_strength;

	ALBEDO = mix(water_color, sky_tint, fresnel);
	ROUGHNESS = water_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	// El borde de canto se cierra un poco más que el centro: es lo que hace que
	// la orilla no se vea como un recorte de papel sobre la arena.
	ALPHA = clamp(water_alpha + fresnel * 0.5, 0.0, 1.0);
}
