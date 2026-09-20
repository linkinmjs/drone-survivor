## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ajustes de la percepción de un enemigo (`docs/06` §9 y §15).
##
## Todo el ruido, la memoria y el patrón de búsqueda de [Perception] salen de
## acá: el nodo no tiene ningún número propio. Los valores por defecto son los
## de `docs/06` §15 y `docs/07` §12.
class_name PerceptionProfile extends Resource

## Frecuencia de muestreo, en Hz. `docs/06` §9 la fija en 10 y la resuelve con
## un acumulador dentro de `_physics_process`, nunca con un [Timer].
@export_range(1.0, 60.0, 0.5) var hz: float = 10.0

## Desviación típica del ruido de posición con el dron quieto, en metros.
@export_range(0.0, 20.0, 0.05) var noise_base: float = 2.0

## Cuánto crece la desviación por cada m/s de velocidad del dron.
@export_range(0.0, 2.0, 0.01) var noise_speed_factor: float = 0.25

## Constante de tiempo del filtro paso bajo de la creencia, en segundos.
@export_range(0.01, 5.0, 0.01) var filter_tau: float = 0.35

## Segundos que el enemigo sigue extrapolando tras perder la línea de visión.
@export_range(0.0, 60.0, 0.1) var memory_seconds: float = 4.5

## Multiplicador del ruido mientras dura la ceguera (visor roto, EMP, bengala).
@export_range(1.0, 20.0, 0.1) var blind_noise_multiplier: float = 5.0

## Memoria recortada mientras dura la ceguera, en segundos.
@export_range(0.0, 60.0, 0.1) var blind_memory_seconds: float = 1.5

## Radio inicial de la espiral de búsqueda, en metros.
@export_range(0.0, 200.0, 0.5) var search_radius_start: float = 8.0

## Radio final de la espiral de búsqueda, en metros.
@export_range(0.0, 400.0, 0.5) var search_radius_end: float = 45.0

## Segundos que tarda la espiral en ir del radio inicial al final.
@export_range(0.5, 60.0, 0.1) var search_seconds: float = 6.0

## Cada cuántos segundos se regenera el punto de búsqueda (`docs/06` §9 punto 4).
@export_range(0.1, 30.0, 0.1) var search_refresh: float = 2.0

## Parte desde la que sale el rayo de línea de visión. Si no existe se prueba
## con [member head_fallback_name] y, en última instancia, con el propio nodo.
@export var head_node_name: StringName = &"wp_head_visor"

## Parte de reserva para el rayo de línea de visión.
@export var head_fallback_name: StringName = &"hull"

## Máscara del rayo de línea de visión: `world | city` (`docs/02` §3.3). No
## incluye `enemy_body`, así que el enemigo nunca se auto-ocluye.
@export_flags_3d_physics var los_mask: int = PhysicsLayers.QUERY_LOS
