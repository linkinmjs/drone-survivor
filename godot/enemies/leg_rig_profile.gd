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
##
## **WP-24d lo baja de 3.5 a 3.0**: el objetivo de paso lo usa dos veces —para
## decidir cuándo despegar y para centrar la zancada—, así que también fija
## cuánto se aleja el tobillo de la cadera en el instante de apoyar. Con el
## reposo 5 m más afuera, 3.5 m de deriva longitudinal dejaban la rodilla en
## 8.1 m; con 3.0 no baja de 8.6 m ni en el peor tranco.
@export_range(0.1, 40.0, 0.1) var step_trigger: float = 3.0

## Distancia de retraso que dispara un paso **girando en el sitio**, en metros.
##
## Girando, el pie se desplaza de costado, y de costado la pata ya nace a
## [member stance_spread] de la cadera: con los 3.0 m de [member step_trigger] el
## tobillo se iba a 7.6 m en horizontal y la cadena se quedaba sin alcance. Con
## 1.6 m el coloso da **pasos cortos en el lugar**, que es lo que hace un
## cuadrúpedo pesado al girar, y ningún pie arrastra: 0.003 m medidos en el giro
## de 180° de `gait_check`.
@export_range(0.1, 40.0, 0.1) var turn_step_trigger: float = 1.6

## Fracción del alcance de la cadena que también dispara un paso (WP-17).
##
## Es el segundo disparador de `docs/06` §8.4, el de la cadena estirada, escrito
## como fracción en vez de como bandera: por debajo de 1.0 la pata pide el paso
## **antes** de quedarse sin alcance, que es lo que hace falta cuando el
## [GaitController] puede hacerla esperar un tranco entero. Con 1.0 se comporta
## exactamente como el `stretched` del documento; con [member stretch_max] o más
## se desactiva y manda sólo [member step_trigger].
##
## **WP-24d lo sube de 0.85 a 0.95**: con la zancada centrada del objetivo de
## paso, el tramo cadera→tobillo llega legítimamente al 88 % de la cadena en el
## instante de apoyar en llano y al 94 % en la rampa de 20°. Con 0.85 las cuatro
## patas pedían turno **en cada tick** de la rampa, el [GaitController] se lo
## negaba y la marcha se volvía un forcejeo. A 0.95 el disparador vuelve a ser lo
## que el documento quería: la red de seguridad de la cadena, no el metrónomo.
@export_range(0.5, 2.0, 0.01) var reach_trigger: float = 0.95

## Duración nominal de un paso a [member speed_ref], en segundos.
##
## **WP-24d lo sube de 0.55 a 0.80**: 0.55 s daban 1.8 trancos por segundo y por
## pata, un ritmo de insecto para 900 t. Con 0.80 s la cadencia baja a un apoyo
## de par cada 0.98 s y el ciclo completo dura 1.97 s, que es lo que hace que el
## coloso se lea pesado.
@export_range(0.05, 5.0, 0.01) var step_duration: float = 0.80

## Altura mínima del arco del paso, en metros.
@export_range(0.0, 20.0, 0.1) var step_height_min: float = 3.5

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
##
## **WP-24d lo sube de 0.6 a 0.75**: con 0.6 el cuerpo seguía la rampa de 20° a
## 12° y los 8° de desajuste los pagaban las patas —1.6 m más de extensión en el
## par de abajo, que se quedaba recto como un puntal—. Con 0.75 la rampa se
## camina a 15°, dentro de la banda [8°, 16°] de `docs/06` §16.2, y al par de
## abajo le quedan 6 % de cadena de margen.
@export_range(0.0, 1.0, 0.01) var tilt_blend: float = 0.75

## Ritmo de suavizado de la inclinación del cuerpo, en s⁻¹. WP-24d lo sube de
## 4.0 a 6.0 para que el balanceo del ciclo (`gait_roll`/`gait_pitch`) no llegue
## amortiguado a la mitad.
@export_range(0.1, 40.0, 0.1) var tilt_smooth_rate: float = 6.0

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

## Ensanchamiento **lateral** de la postura de marcha sobre la huella de reposo
## del modelo, en metros hacia afuera en X (WP-17, corregido en WP-24d).
##
## Hasta WP-24d el ensanchamiento era **radial desde el origen del cuerpo**, y
## como las patas del Arachnodroid están en (±6, 0, ∓11.625) esa dirección es
## sobre todo ±Z: separar 1.5 m movía los pies hacia adelante y hacia atrás, no
## hacia afuera, y el tobillo se quedaba a 2.5 m de la cadera en horizontal. Con
## la cadena casi vertical el fémur baja 6.1 m y la rodilla queda a **7.9 m**,
## metida bajo la panza. Con 5.0 m de separación lateral el tobillo queda a 4.6 m
## de la cadera, el fémur se inclina hacia afuera y la rodilla sube a **9.4 m**
## —8.6 m en el peor instante del tranco— sin tocar `hip_height`, que
## `docs/07` §2 fija en 14.0 m por silueta.
##
## El tope sigue siendo la cadena: con los pies a ±11.0 m —el ancho del anillo
## de hombros— el tramo cadera→tobillo mide 11.3 m de los 13.59 m disponibles
## (83 %), y llega al 88 % en el instante de apoyar. Con 0.0 el rig usa la
## huella del GLB tal cual.
@export_range(0.0, 20.0, 0.1) var stance_spread: float = 5.0

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

# --------------------------------------------------------------------------
# Peso y cadencia de la marcha (WP-24d)
# --------------------------------------------------------------------------

## Rebote vertical del cuerpo acoplado al ciclo de paso, como fracción de
## `hip_height`.
##
## La cadera baja en cada intercambio de pares y sube a media zancada: es el
## acento que convierte cuatro patas moviéndose en una marcha. Con 0.02 y una
## cadera de 14 m el recorrido es de ±0.28 m, muy por debajo del ±1 m que tolera
## la métrica 5 de `docs/06` §16.2.
@export_range(0.0, 0.2, 0.001) var body_bob: float = 0.02

## Alabeo del cuerpo en fase con el ciclo de paso, en grados.
@export_range(0.0, 15.0, 0.1) var gait_roll: float = 2.0

## Cabeceo del cuerpo en fase con el ciclo de paso, en grados. Sumado a
## [member gait_roll] queda por debajo de los 6° que WP-24d exige en llano.
@export_range(0.0, 15.0, 0.1) var gait_pitch: float = 1.5

## Segundos que tarda el factor de paso en pasar de una marcha a la otra.
@export_range(0.0, 5.0, 0.05) var gait_blend_time: float = 0.45

## Amplitud de la respiración de servos en reposo, en metros.
##
## Sin esto el coloso quieto es una estatua: el rig no toca un solo hueso
## mientras no haya un paso que dar. `docs/07` §5.2 pide presión ambiental
## también cuando no camina.
@export_range(0.0, 2.0, 0.01) var idle_breath: float = 0.15

## Frecuencia de la respiración de servos, en Hz.
@export_range(0.05, 4.0, 0.01) var idle_breath_hz: float = 0.30

## Flexión de rodillas del aterrizaje, como fracción de `hip_height`.
##
## Al tocar el suelo el cuerpo se hunde y vuelve, en vez de aparecer ya a su
## altura nominal. Es la única parte del salto que da peso al aterrizaje
## (`docs/06` §8.6 punto 4 y `docs/13` §6).
@export_range(0.0, 0.6, 0.01) var land_crouch: float = 0.12

## Duración del ciclo de flexión del aterrizaje, en segundos.
@export_range(0.0, 2.0, 0.01) var land_crouch_time: float = 0.30

## Cabeceo mínimo del cuerpo mientras trepa, en grados (`docs/07` §5.3).
##
## Es un **piso**, no una suma: si el plano de apoyo ya inclina el morro más que
## esto, el rig no agrega nada. Así el cabeceo del trepado se lee siempre igual,
## suba a un bloque de 8 m o a una torre de 30.
@export_range(0.0, 60.0, 0.5) var climb_pitch: float = 25.0
