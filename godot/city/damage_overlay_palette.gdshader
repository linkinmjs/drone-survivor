// Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
//
// Etapa DAMAGED de una pieza con **paleta de 256×1** (`assets/town/`, WP-A).
//
// Copia exacta de `damage_overlay.gdshader` con una sola diferencia, en la línea
// del `uniform`: `filter_nearest, repeat_disable` en vez de
// `filter_linear_mipmap, repeat_enable`. No es cosmético. La difusa de la ciudad
// es un atlas de 2048² donde el filtrado bilineal ayuda; la del pueblo es la
// paleta de 256×1 del pipeline voxel, donde cada vecino horizontal es **otro
// color sin relación**: con `filter_linear_mipmap` la pared beige (índice 70) se
// mezcla con el índice 71 y, en los mips bajos, con el promedio de toda la
// paleta; `repeat_enable` añade el envoltorio entre el índice 256 y el 1. El
// edificio dañado quedaba gris sucio en vez de conservar su color.
//
// Lo elige `BuildingProfile.damage_shader`: si el perfil lo declara,
// `Building._resolve_damage_material()` lo usa en lugar del de la ciudad.
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

// Difusa de la pieza: la paleta de 256×1 del pipeline voxel (`assets/town/`).
// **Ésta es la única línea que distingue este shader del de la ciudad.**
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;

#include "res://city/damage_overlay_body.gdshaderinc"
