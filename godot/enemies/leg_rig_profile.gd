## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ajustes del rig de patas procedural (`docs/06` §3 y §8).
##
## **WP-16 entrega sólo el `Resource`**: el `ProceduralLegRig`, el IK de dos
## huesos, el `GaitController` y el ciclo de paso son WP-17. Los valores por
## defecto son los de `docs/06` §15 y los que `docs/07` §12 fija para el
## Arachnodroid.
class_name LegRigProfile extends Resource

## Distancia entre el pie y su reposo deseado que dispara un paso, en metros.
@export_range(0.1, 40.0, 0.1) var step_trigger: float = 3.5

## Fracción del alcance de la cadena que también dispara un paso (WP-17).
##
## Es el segundo disparador de `docs/06` §8.4, el de la cadena estirada, escrito
## como fracción en vez de como bandera: por debajo de 1.0 la pata pide el paso
## **antes** de quedarse sin alcance, que es lo que hace falta cuando el
## [GaitController] puede hacerla esperar un tranco entero. Con 1.0 se comporta
## exactamente como el `stretched` del documento; con [member stretch_max] o más
## se desactiva y manda sólo [member step_trigger].
@export_range(0.5, 2.0, 0.01) var reach_trigger: float = 0.85

## Duración nominal de un paso a [member speed_ref], en segundos.
@export_range(0.05, 5.0, 0.01) var step_duration: float = 0.55

## Altura mínima del arco del paso, en metros.
@export_range(0.0, 20.0, 0.1) var step_height_min: float = 3.0

## Suma fija a la altura del arco sobre el desnivel salvado, en metros.
@export_range(0.0, 20.0, 0.1) var step_height_bias: float = 2.0

## Velocidad de referencia que normaliza la duración del paso, en m/s.
@export_range(0.1, 40.0, 0.1) var speed_ref: float = 6.0

## Recorte del factor `velocidad / speed_ref` que acelera o alarga el paso.
@export var speed_clamp: Vector2 = Vector2(0.6, 1.8)

## Pares de patas que se mueven juntas en trote diagonal, por índice de pata.
@export var gait_pairs: Array[PackedInt32Array] = [
	PackedInt32Array([0, 3]),
	PackedInt32Array([1, 2]),
]

## Patas apoyadas que el modo trípode garantiza como mínimo.
@export_range(1, 8) var tripod_min_planted: int = 2

## Estiramiento máximo de la cadena fémur + tibia antes de despegar el pie.
@export_range(1.0, 2.0, 0.01) var stretch_max: float = 1.15

## Mezcla entre la vertical y la normal del plano de apoyo, de 0 a 1.
@export_range(0.0, 1.0, 0.01) var tilt_blend: float = 0.6

## Ritmo de suavizado de la inclinación del cuerpo, en s⁻¹.
@export_range(0.1, 40.0, 0.1) var tilt_smooth_rate: float = 4.0

## Ritmo de suavizado de la altura del cuerpo, en s⁻¹.
@export_range(0.1, 40.0, 0.1) var height_smooth_rate: float = 4.0

## Media longitud del rayo de apoyo del pie, en metros (±40 m).
@export_range(1.0, 200.0, 0.5) var foot_ray_span: float = 40.0

## Máscara del rayo de apoyo: capas 1 (`world`) y 8 (`city`) = 129.
@export_flags_3d_physics var foot_ray_mask: int = 129

## Daño al edificio sobre el que se apoya un pie (`docs/07` §5.2).
@export_range(0.0, 10000.0, 1.0) var crush_damage: float = 900.0

## Tiempo de recogida de patas antes del vuelo balístico, en segundos.
@export_range(0.0, 5.0, 0.05) var leap_tuck_time: float = 0.5

## Ensanchamiento de la postura de marcha sobre la huella de reposo del modelo,
## en metros hacia afuera (WP-17).
##
## La pose de reposo del Arachnodroid trae la cadena al 99.7 % de extensión
## (13.55 m de 13.59 m): con la cadera bajada a `hip_height` la rodilla ya se
## dobla, y abrir un poco la huella la levanta hacia la silueta del modelo y
## agranda el polígono de apoyo. Con 0.0 el rig usa la huella del GLB tal cual.
@export_range(0.0, 20.0, 0.1) var stance_spread: float = 1.5

## Ritmo de suavizado general de la pose del cuerpo, en s⁻¹ (`docs/06` §8.5).
##
## [member height_smooth_rate] y [member tilt_smooth_rate] mandan en la altura y
## en la inclinación de la marcha; éste gobierna el resto de las transiciones de
## pose: el agazapado del `tuck`, la recuperación del aterrizaje y la caída a
## `DOWNED`.
@export_range(0.1, 40.0, 0.1) var body_smoothing: float = 4.0

## Multiplicador de velocidad mientras el cuerpo se arrastra con 2 patas
## (`docs/06` §8.3).
@export_range(0.0, 1.0, 0.01) var drag_speed_factor: float = 0.55

## Distancia horizontal máxima de un salto, en metros (`docs/06` §8.6).
@export_range(1.0, 200.0, 0.5) var jump_max_distance: float = 60.0

## Altura máxima del vértice de la parábola del salto, en metros.
@export_range(1.0, 120.0, 0.5) var jump_max_height: float = 25.0

## Antelación con la que se predicen los cuatro puntos de impacto y se estiran
## los pies hacia ellos, en segundos (`docs/06` §8.6 punto 3).
@export_range(0.0, 2.0, 0.01) var land_predict: float = 0.35

## Tambaleo con el que se paga el aterrizaje, en segundos (`docs/06` §8.6
## punto 4).
@export_range(0.0, 5.0, 0.05) var land_stagger: float = 0.35

## Gravedad del vuelo balístico, en m/s² (`docs/06` §8.6 punto 2).
@export_range(0.1, 40.0, 0.01) var leap_gravity: float = 9.81

## Tope de desplazamiento por tick durante el vuelo, en metros. Dobla el de
## `EnemyProfile.max_step_per_tick` porque en el aire el coloso no toca nada
## salvo el suelo (`docs/06` §8.6 punto 2).
@export_range(0.05, 10.0, 0.05) var leap_max_step: float = 1.2

## Tiempo de interpolación del re-balance de `rest_offset` al perder una pata,
## en segundos (`docs/06` §8.7).
@export_range(0.0, 10.0, 0.05) var rebalance_time: float = 1.2

## Fracción de `hip_height` a la que cae la cadera al entrar en `DOWNED`.
@export_range(0.0, 1.0, 0.01) var downed_hip_factor: float = 0.35

## Altura del **origen del cuerpo** sobre el suelo cuando el enemigo está
## `DOWNED`, en metros. Negativa: el cuerpo se hunde por debajo del origen del
## modelo hasta que la panza apoya.
##
## Reemplaza a [member downed_hip_factor] para la pose de caído, que daba
## `0.35 · 14 − 17.25 = −12.35 m`: el coloso se enterraba, los tres `wp_core_*`
## quedaban **bajo el suelo** y no se exponían nunca, así que la ronda no
## terminaba jamás (medido en WP-23). Con `−6.0` la cara inferior de
## `underbelly` —a `+6.5` en local— apoya con 0.5 m de margen y los núcleos
## quedan a unos 6.5 m sobre el suelo, alcanzables de costado.
##
## [member downed_hip_factor] se conserva porque `docs/06` §8.7 lo nombra y el
## bot lo documenta, pero ya no decide la altura del cuerpo caído.
@export_range(-40.0, 40.0, 0.1) var downed_body_height: float = -6.0

## Amplitud del bamboleo del tambaleo, en grados (`docs/06` §7 punto 6).
@export_range(0.0, 30.0, 0.1) var stagger_wobble: float = 4.0

## Frecuencia del bamboleo del tambaleo, en Hz.
@export_range(0.1, 30.0, 0.1) var stagger_frequency: float = 5.0
