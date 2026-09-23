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

// Difusa de la familia de la pieza (`assets/city/textures/`). El atlas es de 2048²
// y el filtrado bilineal con mipmaps ayuda.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

#include "res://city/damage_overlay_body.gdshaderinc"
