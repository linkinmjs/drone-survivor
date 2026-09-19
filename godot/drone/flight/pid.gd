## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## PID en forma paralela para un eje del lazo de tasa (`docs/03` §3.4).
##
## `u = Kp·e + Ki·∫e·dt − Kd·d(medida)/dt`. Tres decisiones que no son cosméticas:
##
## 1. **Derivada sobre la medida, no sobre el error.** Un escalón de stick cambia
##    la consigna de golpe; derivar el error daría una patada de salida que el
##    mezclador convertiría en un salto de régimen. Derivando la medida, el
##    escalón solo entra por el término proporcional.
## 2. **Paso bajo de primer orden a [constant DERIVATIVE_CUTOFF_HZ]** sobre esa
##    derivada. A 1 000 Hz de lazo, la diferencia entre dos medidas consecutivas
##    amplifica cualquier ruido del integrador por `1/dt`; el filtro lo deja en la
##    banda donde de verdad hay dinámica de cuerpo rígido.
## 3. **Anti-windup por saturación condicional.** La integral solo se acumula si
##    la salida resultante no queda pegada al tope en el mismo sentido del error.
##    Es lo que evita que un tope mecánico —el mezclador saturado— deje el
##    integrador cargado y el dron siga girando después de soltar el stick.
##
## La integral se acota a ±[constant INTEGRAL_LIMIT] y la salida a
## ±[constant OUTPUT_LIMIT], ambas en unidades de comando de motor.
class_name PIDController extends RefCounted

## Tope del término integral, en unidades de salida (`docs/03` §3.4).
const INTEGRAL_LIMIT: float = 0.3

## Tope de la salida, en unidades de comando de motor.
const OUTPUT_LIMIT: float = 1.0

## Frecuencia de corte del paso bajo de la derivada, en Hz (`docs/03` §10).
const DERIVATIVE_CUTOFF_HZ: float = 40.0

## Ganancia proporcional, en unidades de salida por rad/s de error.
var kp: float = 0.0

## Ganancia integral, en unidades de salida por rad de error acumulado.
var ki: float = 0.0

## Ganancia derivativa, en unidades de salida por rad/s².
var kd: float = 0.0

## Último valor del término integral. Solo lectura desde fuera; lo usan el HUD de
## depuración y los checks.
var integral: float = 0.0

## Derivada de la medida ya filtrada, en unidades de medida por segundo.
var derivative: float = 0.0

## Última salida devuelta por [method update], ya acotada.
var output: float = 0.0

var _last_measurement: float = 0.0
var _has_measurement: bool = false

## Constante de tiempo del paso bajo: `RC = 1 / (2π·f)`.
var _filter_rc: float = 1.0 / (TAU * DERIVATIVE_CUTOFF_HZ)


## Construye el PID con sus tres ganancias ya puestas.
func _init(p_kp: float = 0.0, p_ki: float = 0.0, p_kd: float = 0.0) -> void:
	set_gains(p_kp, p_ki, p_kd)


## Fija las tres ganancias de una vez. No toca el estado interno: cambiar de
## perfil en vuelo no debe provocar un salto de salida.
func set_gains(p_kp: float, p_ki: float, p_kd: float) -> void:
	kp = p_kp
	ki = p_ki
	kd = p_kd


## Copia las tres ganancias desde un `Vector3` `(Kp, Ki, Kd)`.
func set_gains_vector(gains: Vector3) -> void:
	set_gains(gains.x, gains.y, gains.z)


## Avanza el lazo [param dt] segundos y devuelve la salida acotada a
## ±[constant OUTPUT_LIMIT].
##
## [param setpoint] y [param measurement] van en las mismas unidades (rad/s en el
## lazo de tasa). Devuelve 0 con un [param dt] nulo o negativo.
func update(setpoint: float, measurement: float, dt: float) -> float:
	if dt <= 0.0 or not is_finite(setpoint) or not is_finite(measurement):
		return output
	var error := setpoint - measurement

	# Derivada sobre la medida: el primer paso no tiene con qué comparar, así que
	# arranca en cero en vez de inventar un escalón infinito.
	var raw_derivative := 0.0
	if _has_measurement:
		raw_derivative = (measurement - _last_measurement) / dt
	_last_measurement = measurement
	_has_measurement = true
	var alpha := dt / (_filter_rc + dt)
	derivative += (raw_derivative - derivative) * alpha

	var proportional := kp * error
	var damping := -kd * derivative
	# Se integra «a prueba»: el valor candidato solo se confirma si la salida que
	# produce no queda saturada empujando en el mismo sentido que el error.
	var candidate := clampf(integral + ki * error * dt, -INTEGRAL_LIMIT, INTEGRAL_LIMIT)
	var unclamped := proportional + candidate + damping
	var saturated_high := unclamped > OUTPUT_LIMIT and error > 0.0
	var saturated_low := unclamped < -OUTPUT_LIMIT and error < 0.0
	if not saturated_high and not saturated_low:
		integral = candidate

	output = clampf(proportional + integral + damping, -OUTPUT_LIMIT, OUTPUT_LIMIT)
	return output


## Vacía integral, filtro y memoria de la medida. Lo llaman el armado, el desarme
## y cada cambio de modo (`docs/03` §3.4).
func reset() -> void:
	integral = 0.0
	derivative = 0.0
	output = 0.0
	_last_measurement = 0.0
	_has_measurement = false


func _to_string() -> String:
	return "PIDController(Kp %.4f, Ki %.4f, Kd %.5f, I %.4f, u %.4f)" \
			% [kp, ki, kd, integral, output]
