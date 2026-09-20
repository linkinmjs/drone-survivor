## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Curvas de utilidad reutilizables (`docs/06` §10.2).
##
## Son funciones puras y estáticas: ninguna guarda estado ni mira el árbol. Cada
## [EnemyAction] compone las que necesita dentro de su `score(ctx)` y multiplica
## por sus moduladores. Todas devuelven un valor recortado a `[0, 1]`, que es el
## rango que el [UtilitySelector] espera antes de aplicar personalidad y fase.
class_name ActionScore extends RefCounted


## Recorta a `[0, 1]`. Un `NAN` devuelve 0: una curva rota no puede ganar un
## sorteo.
static func clamp01(value: float) -> float:
	if is_nan(value):
		return 0.0
	return clampf(value, 0.0, 1.0)


## Rampa lineal: 0 en [param from], 1 en [param to]. Funciona en los dos
## sentidos, así que `linear(d, 80, 20)` decrece con la distancia.
static func linear(value: float, from: float, to: float) -> float:
	if is_equal_approx(from, to):
		return 1.0 if value >= to else 0.0
	return clamp01((value - from) / (to - from))


## Campana con el máximo en [param center] y medio ancho [param width]: vale 1
## en el centro y 0 a `width` de él, con caída suave (coseno alzado).
##
## Es la forma de `stomp` y de `head_laser`: un ataque que vive en una banda de
## distancia y muere pegado al cuerpo y muy lejos.
static func bell(value: float, center: float, width: float) -> float:
	if width <= 0.0:
		return 1.0 if is_equal_approx(value, center) else 0.0
	var t := clampf(absf(value - center) / width, 0.0, 1.0)
	return clamp01(0.5 + 0.5 * cos(PI * t))


## Preferencia por lo cercano: 1 pegado al enemigo y 0 en [param max_range].
static func inverse_distance(distance: float, max_range: float) -> float:
	if max_range <= 0.0:
		return 0.0
	return clamp01(1.0 - distance / max_range)


## Disponibilidad por enfriamiento: 0 mientras falta, 1 en cuanto vence.
##
## [param remaining] son los segundos que quedan de `cooldown`. La rampa es
## dura a propósito: el descarte por enfriamiento lo hace
## [method EnemyAction.can_run]; esto es sólo para curvas que quieran
## [i]anticipar[/i] la disponibilidad.
static func cooldown_ready(remaining: float, cooldown: float) -> float:
	if remaining <= 0.0:
		return 1.0
	if cooldown <= 0.0:
		return 1.0
	return clamp01(1.0 - remaining / cooldown)


## Evalúa una [Curve] de `docs/06` §10.2 sobre [param value] ya normalizado a
## `[0, 1]`. Sin curva devuelve [param fallback].
static func from_curve(curve: Curve, value: float, fallback: float = 0.0) -> float:
	if curve == null:
		return clamp01(fallback)
	return clamp01(curve.sample_baked(clampf(value, 0.0, 1.0)))


## Modulador booleano: 1.0 si [param condition], si no [param penalty].
static func gate(condition: bool, penalty: float = 0.0) -> float:
	return 1.0 if condition else clamp01(penalty)
