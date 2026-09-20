## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Todos los números de la economía de energía en un [Resource] (`docs/09` §3.3).
##
## La razón de que esto sea un recurso y no constantes dentro de [EnergySystem] es
## el balance: `docs/09` §6 deja abierto el mayor riesgo del documento —los 35 s de
## autonomía en combate— y anticipa que WP-23 baje [member base_drain] a 0.35, suba
## [member battery_amount] a 40 o toque [member throttle_drain]. Con los valores
## acá nadie tiene que recompilar ni tocar una línea de lógica.
##
## El recurso del MVP vive en `res://drone/energy/profiles/default_energy.tres` con
## los valores cerrados del Anexo A/C (`docs/09` §4).
##
## **Escala 0–100, no normalizada** (`docs/09` §2.1): todos los valores del Anexo C
## están en porcentaje y guardarlos así evita conversiones dispersas. Lo único que
## viaja normalizado es [method EnergySystem.get_ratio], que es lo que consume el
## bus.
class_name EnergyProfile extends Resource

## Energía máxima de la batería, en la escala 0–100 de `docs/09` §2.1.
@export_range(1.0, 1000.0) var max_energy: float = 100.0

# --- Drenaje (`docs/09` §2.1) -----------------------------------------------------------------

## Drenaje base mientras el dron está **armado**, en %/s. Se paga aunque el
## acelerador esté a cero: son los ESC, la radio y la electrónica.
@export_range(0.0, 10.0) var base_drain: float = 0.55

## Drenaje adicional a acelerador pleno, en %/s. El drenaje total es
## `base_drain + throttle_drain * throttle`.
@export_range(0.0, 10.0) var throttle_drain: float = 0.85

## Recarga por segundo con el dron **desarmado**, en %/s (`docs/09` §2.1).
##
## **Apagada desde WP-24e** (`idle_recharge = 0`). La recarga en reposo existía como
## única salida del bloqueo a 0 %, y esa salida ahora es la reconstrucción: a batería
## agotada el dron se reconstruye como si muriera y vuelve con
## [member respawn_energy_depleted]. Dejar las dos cosas a la vez regalaba autonomía
## gratis —bastaba desarmar y esperar— y además producía el ciclo de 1 % que el
## piloto veía como «arma, cae, arma, cae». El campo se conserva porque el balance de
## WP-23 puede querer volver a encenderlo.
@export_range(0.0, 10.0) var idle_recharge: float = 0.0

## Techo de la recarga en reposo, en la escala 0–100.
##
## Es un **techo absoluto**: la recarga solo actúa mientras `energy` esté por
## debajo de este valor. Con [member idle_recharge] en 0 no hace nada; se conserva,
## igual que el otro campo, para el día que WP-23 quiera reactivar el mecanismo.
@export_range(0.0, 100.0) var idle_recharge_cap: float = 0.0

# --- Estados (`docs/09` §2.2) -----------------------------------------------------------------

## Fracción bajo la cual se entra en estado crítico.
@export_range(0.0, 1.0) var critical_ratio: float = 0.15

## Fracción a partir de la cual se **sale** del estado crítico.
##
## La histéresis (entrar a 15 %, salir a 18 %) es lo que evita que el aviso del HUD
## y la escala de empuje parpadeen mientras la energía oscila alrededor del umbral
## con cada disparo.
@export_range(0.0, 1.0) var critical_exit_ratio: float = 0.18

## Factor de empuje máximo mientras la energía es crítica (`docs/03` §9).
@export_range(0.1, 1.0) var critical_thrust_scale: float = 0.82

# --- Fuentes externas -------------------------------------------------------------------------

## Energía que devuelve una [BatteryPickup], en la escala 0–100.
@export_range(0.0, 100.0) var battery_amount: float = 30.0

## Energía que roba el `emp_pulse` del jefe (`docs/07`).
@export_range(0.0, 100.0) var emp_drain: float = 25.0

## Duración del glitch de interfaz que dispara el EMP, en segundos. Viaja por la
## señal local [signal EnergySystem.emp_hit] (`docs/09` §2.9).
@export_range(0.0, 10.0) var emp_glitch_seconds: float = 3.0

## Energía con la que reaparece el dron tras un respawn **por casco**
## (`docs/09` §2.8).
@export_range(0.0, 100.0) var respawn_energy: float = 60.0

## Energía con la que reaparece el dron tras un respawn **por batería agotada**.
##
## Es menos que [member respawn_energy] a propósito: quedarse sin batería es un
## error de gestión del piloto, no un golpe del jefe, y la reconstrucción ya cuesta
## los mismos 12 s, los −300 puntos y el ×0.6. Devolver 60 % convertiría el
## agotamiento en una recarga cara pero cómoda; con 20 % el dron vuelve con el
## tiempo justo para ir a una pila, que es exactamente la decisión que el piloto no
## tomó a tiempo.
@export_range(0.0, 100.0) var respawn_energy_depleted: float = 20.0

# --- Publicación ------------------------------------------------------------------------------

## Variación mínima de `ratio` que obliga a emitir `Events.energy_changed`
## (`docs/09` §2.2). Un cambio de estado la emite siempre, sin importar el delta.
@export_range(0.0001, 0.5) var publish_epsilon: float = 0.005
