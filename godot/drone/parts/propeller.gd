## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hélice de 5.1 pulgadas y tres palas: convierte el régimen del motor en empuje,
## par y arrastre en plano (`docs/03` §2.3).
##
## Modelo, todo de teoría estándar de hélices (`docs/03` §13):
## - Empuje estático `T0 = C_T · ρ · n² · D⁴` y par `Q = C_Q · ρ · n² · D⁵`, con
##   `n = |rpm| / 60` en rev/s y `ρ = 1.225 kg/m³`.
## - Corrección por vuelo hacia delante con la relación de avance
##   `J = V_a / (n · D)`: `T = T0 · clamp(1 − k_J · J, 0.2, 1.2)`. Subir resta
##   empuje, descender lo suma hasta 1.2×.
## - Arrastre en plano `F_h = −k_h · n · D² · v_plano`, que es de dónde sale la
##   amortiguación natural de la traslación.
## - Efecto suelo de Cheeseman-Bennett: `T_ige = T / (1 − (R/(4z))²)` con la
##   altura `z` acotada a `>= R/2`, o sea un factor máximo de 1.33.
##
## Valores finales de los coeficientes (WP-04): **`C_T = 0.11`** y
## **`C_Q = 0.009`**, los propuestos por `docs/03` §10 sin retoque. Con ellos, a
## 30 000 rpm cada hélice da **9.474 N**, los cuatro motores **37.90 N** y la
## relación empuje/peso sobre 0.70 kg queda en **5.52**, dentro del `[4, 6]` de
## §11.2; el comando de equilibrio cae en **0.395**, dentro del `[0.35, 0.55]`
## de §11.1. No hizo falta ajustar ninguno de los dos.
##
## Valor final de la relación de avance (WP-05): **`k_J = 1.0`**, no el 0.6 que
## propone `docs/03` §10. Es el ajuste que §11.6 autoriza para entrar en el rango
## de velocidad máxima: con `k_J = 0.6` el banco medía **51.3 m/s** a 45° de
## inclinación y acelerador a fondo, por encima del techo de 40 m/s; con 1.0 y el
## arrastre simétrico final del cuerpo mide **34.2 m/s**. El valor no se movió al
## corregir el arrastre en la revisión de WP-05: 1.0 ya es el tope físico razonable
## para esta hélice. El cambio va hacia lo físicamente más fiel para ella:
## 5.1" x 4.8" es un paso corto, y una pala de paso corto pierde ángulo de ataque
## —y con él empuje— mucho antes que una de paso largo cuando el aire le entra
## por el eje. Lo acompaña el arrastre del cuerpo, simétrico en X/Z y documentado
## en `drone.gd`. Ninguno de los dos toca §11.1–§11.3, que se miden con la hélice
## quieta respecto del aire.
class_name DronePropeller extends Node3D

## Densidad del aire a nivel del mar, en kg/m³.
const AIR_DENSITY: float = 1.225

## Por debajo de este régimen en rev/s no se calcula la relación de avance: la
## división por `n · D` explotaría con la hélice casi parada.
const MIN_REV_PER_SECOND: float = 1.0

## Eficiencia de la hélice girando al revés (`docs/03` §2.2): la mitad.
const REVERSE_EFFICIENCY: float = 0.5

## Cota inferior del denominador de Cheeseman-Bennett, coherente con `z >= R/2`.
const MIN_GROUND_DENOMINATOR: float = 0.75

## Valor de `height_agl` que significa «el rayo no tocó nada».
const NO_GROUND: float = -1.0

## Diámetro en metros. 5.1 pulgadas son 0.1295 m.
@export var diameter: float = 0.1295

## Número de palas. No entra en las fórmulas —ya está dentro de los coeficientes—
## pero lo consumen el audio (frecuencia de paso de pala) y el desenfoque visual.
@export_range(2, 6, 1) var blades: int = 3

## Coeficiente de empuje.
@export var c_t: float = 0.11

## Coeficiente de par.
@export var c_q: float = 0.009

## Sensibilidad del empuje a la relación de avance.
@export var k_j: float = 1.0

## Coeficiente de arrastre en plano, en `N·s/(m·rev)`.
@export var k_h: float = 0.004

## Permite desactivar el efecto suelo por completo (lo usa `flight_bench`).
@export var ground_effect_enabled: bool = true

## Rayo hacia abajo que mide la altura de esta hélice sobre el terreno. Se
## resuelve en [method _ready]; sin él, [method measure_height_agl] devuelve
## [constant NO_GROUND] y no hay efecto suelo.
var ground_ray: RayCast3D = null


func _ready() -> void:
	ground_ray = get_node_or_null(^"GroundRay") as RayCast3D


## Fuerzas y momentos que esta hélice produce a [param rpm].
##
## [param velocity_of_prop_world] es la velocidad del punto donde está la hélice
## (la del cuerpo más `ω × r`), en coordenadas de mundo. [param axis_world] es el
## eje de empuje, o sea el `+Y` del cuerpo en mundo. [param height_agl] es la
## altura sobre el terreno en metros, o [constant NO_GROUND] si no hay suelo.
##
## Devuelve `{"thrust": float, "torque": float, "in_plane_force": Vector3}`:
## - `thrust`: newtons a lo largo de [param axis_world]; negativo en reversa.
## - `torque`: módulo del par aerodinámico en N·m, siempre positivo. El signo del
##   par de reacción sobre el cuerpo lo pone quien llama, con `spin · signo(rpm)`
##   (ver [method DroneMotor.get_torque]).
## - `in_plane_force`: newtons, perpendicular al eje, en coordenadas de mundo.
func compute_forces(rpm: float, velocity_of_prop_world: Vector3, axis_world: Vector3,
		height_agl: float) -> Dictionary:
	var result: Dictionary = {
		"thrust": 0.0,
		"torque": 0.0,
		"in_plane_force": Vector3.ZERO,
	}
	if not is_finite(rpm) or is_zero_approx(rpm):
		return result
	var axis := axis_world.normalized()
	if axis.is_zero_approx():
		return result

	var revolutions := absf(rpm) / 60.0
	var squared := revolutions * revolutions
	var d2 := diameter * diameter
	var d4 := d2 * d2

	# Empuje y par estáticos.
	var thrust := c_t * AIR_DENSITY * squared * d4
	result["torque"] = c_q * AIR_DENSITY * squared * d4 * diameter

	# Relación de avance: el aire que entra por el eje resta empuje al subir y lo
	# suma al descender, acotado a `[0.2, 1.2]` para que el modelo no se dé vuelta
	# en un picado rápido.
	var axial_speed := velocity_of_prop_world.dot(axis)
	if revolutions > MIN_REV_PER_SECOND:
		var advance := axial_speed / (revolutions * diameter)
		thrust *= clampf(1.0 - k_j * advance, 0.2, 1.2)

	thrust *= ground_effect_factor(height_agl)
	if rpm < 0.0:
		# Girando al revés la pala trabaja con el perfil invertido: la mitad de
		# empuje y hacia el otro lado (`docs/03` §2.2).
		thrust = -thrust * REVERSE_EFFICIENCY
	result["thrust"] = thrust

	# Arrastre en plano: se opone a la componente de la velocidad perpendicular
	# al eje y es lo que frena la traslación cuando el piloto suelta los sticks.
	var in_plane := velocity_of_prop_world - axis * axial_speed
	result["in_plane_force"] = in_plane * (-k_h * revolutions * d2)
	return result


## Par aerodinámico en N·m a [param rpm], sin corregir por avance ni por suelo.
## Es el que alimenta el par de reacción del motor.
func static_torque(rpm: float) -> float:
	if not is_finite(rpm):
		return 0.0
	var revolutions := absf(rpm) / 60.0
	var d2 := diameter * diameter
	return c_q * AIR_DENSITY * revolutions * revolutions * d2 * d2 * diameter


## Empuje estático en newtons a [param rpm], sin avance ni efecto suelo. Lo usa
## `flight_bench` para la bisección del hover y la relación empuje/peso.
func static_thrust(rpm: float) -> float:
	if not is_finite(rpm):
		return 0.0
	var revolutions := absf(rpm) / 60.0
	var d2 := diameter * diameter
	var thrust := c_t * AIR_DENSITY * revolutions * revolutions * d2 * d2
	return -thrust * REVERSE_EFFICIENCY if rpm < 0.0 else thrust


## Multiplicador de empuje por efecto suelo a [param height_agl] metros.
##
## Cheeseman-Bennett con `R = D/2`: el factor crece al acercarse al piso y se
## corta en 1.3333 al acotar `z >= R/2`. Sin suelo a la vista devuelve 1.
func ground_effect_factor(height_agl: float) -> float:
	if not ground_effect_enabled:
		return 1.0
	if height_agl < 0.0 or not is_finite(height_agl):
		return 1.0
	var prop_radius := diameter * 0.5
	var height := maxf(height_agl, prop_radius * 0.5)
	var ratio := prop_radius / (4.0 * height)
	var denominator := maxf(1.0 - ratio * ratio, MIN_GROUND_DENOMINATOR)
	return 1.0 / denominator


## Altura de la hélice sobre el terreno en metros, leída del rayo hijo.
##
## Devuelve [constant NO_GROUND] si no hay rayo o si no está tocando nada. El
## valor es el de la última actualización del `RayCast3D`, que ocurre una vez por
## tick de física: dentro de los diez sub-pasos se considera constante, lo que a
## 100 Hz supone como mucho un centímetro de error en un descenso a 1 m/s.
func measure_height_agl() -> float:
	if ground_ray == null or not ground_ray.is_colliding():
		return NO_GROUND
	var origin := ground_ray.global_transform.origin
	return maxf(origin.distance_to(ground_ray.get_collision_point()), 0.0)


## Radio de la hélice en metros.
func radius() -> float:
	return diameter * 0.5


## Frecuencia de paso de pala en Hz a [param rpm]: `palas · rpm / 60`. La consume
## el sintetizador de audio de motores (`docs/03` §6).
func blade_pass_frequency(rpm: float) -> float:
	return float(blades) * absf(rpm) / 60.0
