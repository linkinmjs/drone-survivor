## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Curvas de rates estilo Betaflight: convierten la deflexión del stick en la
## velocidad angular que pide el piloto, en grados por segundo (`docs/03` §3.6).
##
## Los tres ejes viajan en `Vector3` con la convención `x = roll`, `y = pitch`,
## `z = yaw`. Los parámetros están en las **unidades enteras** de la documentación
## pública de Betaflight (las mismas que muestra el hangar, `docs/04` §4.7), de
## modo que un perfil copiado del configurador da exactamente la misma curva.
##
## Las cinco fórmulas son puras, impares (`f(−x) == −f(x)`) y su salida se acota
## a ±[constant MAX_RATE]. Quien necesite una entrada normalizada usa
## [method get_normalized] en vez de dividir a mano.
class_name ControlProfile extends Resource

## Familias de curva soportadas. El orden es el que persiste `Quad.cfg [rates] curve`
## y el que ofrece el `OptionButton` del hangar; no se reordena.
enum RateCurve {
	ACTUAL,     ## «Actual Rates» de Betaflight: los números ya están en deg/s.
	BETAFLIGHT, ## Curva clásica de Betaflight: rc rate, super rate y expo.
	RACEFLIGHT, ## Raceflight: rate base más Acro+.
	KISS,       ## Controladoras KISS.
	QUICKRATES, ## «Quick Rates» de Betaflight 4.x.
}

## Índice de cada eje dentro de los `Vector3` de parámetros.
enum Axis {
	ROLL,  ## Componente `x`.
	PITCH, ## Componente `y`.
	YAW,   ## Componente `z`.
}

## Tope absoluto de la velocidad angular pedida, en deg/s (`docs/03` §10).
const MAX_RATE: float = 1998.0

## Por debajo de esta tasa máxima, [method get_normalized] devuelve 0 en vez de dividir.
const MIN_DIVISOR: float = 1e-6

## Curva activa.
@export var curve: RateCurve = RateCurve.ACTUAL

## Sensibilidad cerca del centro, por eje (`x` roll, `y` pitch, `z` yaw).
@export var rc_rate: Vector3 = Vector3(7.0, 7.0, 7.0)

## Tasa o «super rate», por eje. Su significado depende de [member curve].
@export var rate: Vector3 = Vector3(67.0, 67.0, 67.0)

## Expo en unidades enteras 0–100, por eje. La fórmula usa `e = expo / 100`.
@export var expo: Vector3 = Vector3(54.0, 54.0, 54.0)


## Velocidad angular en deg/s que pide la deflexión [param x] sobre [param axis].
##
## [param x] se acota a `[−1, 1]` y la salida a ±[constant MAX_RATE]. Un resultado
## no finito (parámetros absurdos guardados a mano en el `.cfg`) se devuelve como 0
## en vez de contaminar el controlador de vuelo.
func get_rate(axis: int, x: float) -> float:
	var index := clampi(axis, int(Axis.ROLL), int(Axis.YAW))
	var deflection := clampf(x, -1.0, 1.0)
	var rc := rc_rate[index]
	var super_rate := rate[index]
	var expo_units := expo[index]
	var omega := 0.0
	match curve:
		RateCurve.BETAFLIGHT:
			omega = _betaflight(deflection, rc, super_rate, expo_units)
		RateCurve.RACEFLIGHT:
			omega = _raceflight(deflection, rc, super_rate, expo_units)
		RateCurve.KISS:
			omega = _kiss(deflection, rc, super_rate, expo_units)
		RateCurve.QUICKRATES:
			omega = _quickrates(deflection, rc, super_rate, expo_units)
		_:
			omega = _actual(deflection, rc, super_rate, expo_units)
	if not is_finite(omega):
		return 0.0
	return clampf(omega, -MAX_RATE, MAX_RATE)


## Velocidad angular con el stick a fondo sobre [param axis], en deg/s.
## Es la etiqueta que el `RateGraph` del hangar escribe encima de cada curva.
func get_max_rate(axis: int) -> float:
	return absf(get_rate(axis, 1.0))


## Misma curva que [method get_rate] pero normalizada a `[−1, 1]` contra
## [method get_max_rate]. La usa el controlador de vuelo cuando un modo (HORIZON)
## necesita una entrada sin unidades y luego la multiplica por su propia tasa.
func get_normalized(axis: int, x: float) -> float:
	var top := get_max_rate(axis)
	if top <= MIN_DIVISOR:
		return 0.0
	return clampf(get_rate(axis, x) / top, -1.0, 1.0)


# --- Fórmulas (`docs/03` §3.6) ----------------------------------------------------------------

## `c = rc_rate·10`; `mx = max(0, rate·10 − c)`; `curva = |x|·(x⁵·e + x·(1 − e))`;
## `ω = x·c + mx·curva`. Con 7 / 67 / 54 da 70 deg/s de centro y 670 de máximo.
static func _actual(x: float, rc: float, rt: float, expo_units: float) -> float:
	var e := expo_units / 100.0
	var center := rc * 10.0
	var extra := maxf(0.0, rt * 10.0 - center)
	var x3 := x * x * x
	var x5 := x3 * x * x
	var shaped := absf(x) * (x5 * e + x * (1.0 - e))
	return x * center + extra * shaped


## `k = rc_rate/100` (con el tramo extra por encima de 2); `x' = x·|x|³·e + x·(1 − e)`;
## `ω = 200·k·x'`, dividido por `clamp(1 − |x|·rate/100, 0.01, 1)` si `rate > 0`.
static func _betaflight(x: float, rc: float, rt: float, expo_units: float) -> float:
	var e := expo_units / 100.0
	var k := rc / 100.0
	if k > 2.0:
		k += 14.54 * (k - 2.0)
	var abs_x := absf(x)
	var shaped := x * abs_x * abs_x * abs_x * e + x * (1.0 - e)
	var omega := 200.0 * k * shaped
	if rt > 0.0:
		omega /= clampf(1.0 - abs_x * rt / 100.0, 0.01, 1.0)
	return omega


## `x' = (1 + 0.01·expo·(x² − 1))·x`; `ω = 10·rc_rate·x'·(1 + |x|·rate·0.01)`.
static func _raceflight(x: float, rc: float, rt: float, expo_units: float) -> float:
	var shaped := (1.0 + 0.01 * expo_units * (x * x - 1.0)) * x
	return 10.0 * rc * shaped * (1.0 + absf(x) * rt * 0.01)


## `s = 1/clamp(1 − |x|·rate/100, 0.01, 1)`; `x' = (x³·e + x·(1 − e))·rc_rate/1000`;
## `ω = 2000·s·x'`.
static func _kiss(x: float, rc: float, rt: float, expo_units: float) -> float:
	var e := expo_units / 100.0
	var boost := 1.0 / clampf(1.0 - absf(x) * rt / 100.0, 0.01, 1.0)
	var shaped := (x * x * x * e + x * (1.0 - e)) * rc / 1000.0
	return 2000.0 * boost * shaped


## `k = rc_rate·2`; `mx = max(rate·10, k)`; `sf = (mx/k − 1)/(mx/k)`;
## `curva = x³·e + x·(1 − e)`; `s = 1/clamp(1 − |x|·sf, 0.01, 1)`; `ω = curva·k·s`.
static func _quickrates(x: float, rc: float, rt: float, expo_units: float) -> float:
	var k := rc * 2.0
	if k <= 0.0:
		return 0.0
	var e := expo_units / 100.0
	var ratio := maxf(rt * 10.0, k) / k
	var super_factor := (ratio - 1.0) / ratio
	var shaped := x * x * x * e + x * (1.0 - e)
	var boost := 1.0 / clampf(1.0 - absf(x) * super_factor, 0.01, 1.0)
	return shaped * k * boost
