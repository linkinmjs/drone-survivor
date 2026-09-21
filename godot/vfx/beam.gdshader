// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Haz de energía (`docs/13` §4). Lo usan `vfx/laser_beam.tscn` (cian del jefe) y
// `vfx/siege_beam.tscn` (ámbar-naranja del asedio, que es la excepción cálida
// porque es luz sobre nuestra ciudad).
//
// Cuatro términos, en el orden en que se ven:
//
//   1. `scroll_speed` — desplazamiento de UV a lo largo del eje del cilindro. Es
//      lo que hace que el haz «corra» hacia el impacto en vez de ser un tubo
//      quieto.
//   2. `fresnel_power` — el borde de silueta del cilindro engorda, así que el
//      tubo se lee como un cilindro de luz y no como una tira plana.
//   3. `pulse_hz` — pulso senoidal de intensidad, para que la energía respire.
//   4. Gradiente radial de `ALPHA` — el haz se apaga en las dos bocas para que no
//      quede cortado a cuchillo contra la cabeza ni contra el punto de contacto.
//
// **`ALBEDO` y no `EMISSION`**: en `unshaded` el resultado es el albedo, y la
// emisión no se suma. Como el umbral de glow de `world/environment_battle.tres`
// es **1,4** (WP-24), `intensity` tiene que dejar el albedo por encima de eso o
// el haz no brilla: con los valores de fábrica el núcleo sale a ~3,2.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled,
		fog_disabled, specular_disabled;

// Color del cuerpo del haz.
uniform vec4 beam_color : source_color = vec4(0.22, 0.78, 1.0, 1.0);

// Color del núcleo, más claro que el cuerpo.
uniform vec4 core_color : source_color = vec4(0.85, 0.98, 1.0, 1.0);

// Vueltas por segundo del scroll de UV a lo largo del eje.
uniform float scroll_speed = 2.4;

// Exponente del término de fresnel; más alto, borde más fino.
uniform float fresnel_power = 2.2;

// Pulsos por segundo de la intensidad.
uniform float pulse_hz = 11.0;

// Multiplicador HDR. Con 1.4 de umbral de glow, por debajo de ~1.6 no brilla.
uniform float intensity = 3.2;

// Bandas del patrón que corre por el eje.
uniform float bands = 3.0;

// Fracción de cada boca que se desvanece, de 0 a 0.5.
uniform float cap_fade : hint_range(0.0, 0.5) = 0.06;

varying vec3 v_normal;
varying vec3 v_view;


void vertex() {
	v_normal = normalize(NORMAL);
	v_view = normalize(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}


void fragment() {
	// 1 · Scroll por el eje del cilindro. El eje de un `CylinderMesh` es `Y`, que
	// en su UV es la coordenada vertical.
	float along = fract(UV.y * bands - TIME * scroll_speed);
	float stripes = 0.62 + 0.38 * sin(along * TAU);

	// 2 · Fresnel: en la silueta la normal es perpendicular a la vista.
	float fresnel = pow(1.0 - abs(dot(v_normal, v_view)), fresnel_power);

	// 3 · Pulso.
	float pulse = 0.86 + 0.14 * sin(TIME * pulse_hz * TAU);

	// 4 · Gradiente radial: las dos bocas se apagan.
	float caps = smoothstep(0.0, cap_fade, UV.y) * smoothstep(1.0, 1.0 - cap_fade, UV.y);

	// El núcleo es lo que queda cuando el fresnel no manda: se ve al mirar el haz
	// de frente y es lo que le da el blanco del centro.
	//
	// El exponente es **6** y no 2: con 2, un haz de 0.25 m de radio a cuarenta
	// metros cae entero dentro del núcleo, sale blanco y pierde el hue que lo
	// identifica —el cian del jefe, el ámbar del asedio— justo cuando el glow lo
	// desparrama. Con 6 el blanco queda reducido a la línea central.
	float core = clamp(1.0 - fresnel, 0.0, 1.0);
	core = core * core * core;
	vec3 tint = mix(beam_color.rgb, core_color.rgb, core * core);
	float energy = (0.45 + 0.85 * fresnel) * stripes * pulse * caps;

	ALBEDO = tint * energy * intensity;
	ALPHA = clamp(energy * beam_color.a, 0.0, 1.0);
}
