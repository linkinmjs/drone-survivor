// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Trazador del arma primaria (`docs/08` §2.9).
//
// El desvanecido NO se calcula en GDScript: el `MultiMesh` escribe la vida del
// proyectil en `INSTANCE_CUSTOM.r` y el fragmento hace `ALPHA *= INSTANCE_CUSTOM.r`.
// Así los 96 trazadores salen en una sola llamada de dibujo y el CPU sólo escribe
// una transformada y un color por instancia y por tick.
//
// `INSTANCE_CUSTOM` = (life, length_scale, 0, 0), con `life` de 1.0 a 0.0.
//
// La malla de origen es un `QuadMesh` unitario en el plano XY, con el eje +Y
// alineado al vuelo por la transformada de la instancia. El vértice lo gira hacia
// la cámara alrededor de ese eje +Y para que el segmento se vea siempre de canto
// (billboard de eje fijo), que es lo que hace creíble una estela recta.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Color del trazador. El brillo alto es deliberado: con `blend_add` y HDR el
// trazador tiene que ganarle al cielo de mediodía.
uniform vec4 tracer_color : source_color = vec4(1.0, 0.72, 0.28, 1.0);

// Energía emisiva del núcleo del trazador.
uniform float emission_energy : hint_range(0.0, 40.0) = 9.0;

// Exponente del desvanecido a lo largo de la vida. Por encima de 1 el trazador
// aguanta brillante casi todo el vuelo y se apaga de golpe al final.
uniform float fade_power : hint_range(0.25, 8.0) = 1.6;

varying float v_life;
varying float v_along;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	// VERTEX del quad unitario va de −0.5 a +0.5 en X e Y; +Y es el eje del vuelo.
	v_along = VERTEX.y + 0.5;

	// Billboard de eje fijo: el eje local +Y (la dirección de vuelo, ya escalada
	// por la transformada de la instancia) se conserva y los otros dos ejes se
	// rehacen mirando a la cámara.
	vec3 axis = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_camera = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - origin;
	vec3 side = cross(axis, to_camera);
	float side_length = length(side);
	// Trazador visto exactamente de punta: no hay plano que orientar, se colapsa.
	side = side_length > 1e-5 ? side / side_length : vec3(0.0);

	float half_width = length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz) * 0.5;
	float half_length = length((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) * 0.5;
	vec3 world = origin + side * (VERTEX.x * 2.0 * half_width) + axis * (VERTEX.y * 2.0 * half_length);

	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// Perfil transversal: el borde del quad se apaga para que el segmento no
	// termine en un canto duro de un píxel.
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	// Perfil longitudinal: la cabeza brilla y la cola se estira.
	float head = smoothstep(0.0, 0.35, v_along);
	float fade = pow(v_life, fade_power);

	ALBEDO = tracer_color.rgb;
	EMISSION = tracer_color.rgb * emission_energy * fade;
	ALPHA = tracer_color.a * across * head * fade;
}
