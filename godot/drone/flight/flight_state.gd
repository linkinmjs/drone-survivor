## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Fotografía del estado del cuerpo rígido que el integrador pasa al controlador
## de vuelo en cada sub-paso (`docs/03` §3.1 y §2.5).
##
## El dron reutiliza **una sola instancia** durante toda su vida y la reescribe
## con [method update] a 1 000 Hz: crear un objeto por sub-paso costaría diez
## asignaciones por tick de física. Quien necesite conservar una lectura usa
## [method copy].
##
## Convenciones de ejes (`docs/03` §2.1 y §3.5):
## - Cuerpo: `−Z` adelante, `+Y` arriba, `+X` derecha.
## - [member angular_velocity] va en **ejes del cuerpo**, crudo, tal como lo pide
##   §3.1: `x` sobre el eje derecha, `y` sobre el eje arriba, `z` sobre el eje atrás.
## - [member euler] y [method rates] van en la convención de **piloto** de §3.5:
##   `x` alabeo (positivo = ala derecha abajo), `y` cabeceo (positivo = morro
##   arriba), `z` guiñada (positivo = morro a la izquierda). El alabeo de piloto
##   es el opuesto de la rotación sobre `+Z`, que apunta hacia atrás.
class_name FlightState extends RefCounted

## Posición del centro de masas en coordenadas de mundo, en metros.
var position: Vector3 = Vector3.ZERO

## Base ortonormal del cuerpo en coordenadas de mundo.
var basis: Basis = Basis.IDENTITY

## Velocidad lineal en coordenadas de **mundo**, en m/s. La versión en ejes del
## cuerpo la da [method body_velocity].
var velocity: Vector3 = Vector3.ZERO

## Velocidad angular en **ejes del cuerpo**, en rad/s.
var angular_velocity: Vector3 = Vector3.ZERO

## Actitud en radianes como `(alabeo, cabeceo, guiñada)`, derivada de
## [member basis] con orden de Euler `YXZ` (`docs/03` §3.1).
var euler: Vector3 = Vector3.ZERO

## Altura sobre el terreno en metros, medida con los rayos de las hélices.
## Vale `−1.0` cuando ningún rayo toca suelo dentro de su alcance.
var altitude_agl: float = -1.0


## Reescribe la instancia con los datos de un sub-paso del integrador.
##
## [param world_angular_velocity] llega en coordenadas de mundo —es lo que
## expone `PhysicsDirectBodyState3D`— y se convierte aquí a ejes del cuerpo.
func update(body_transform: Transform3D, world_velocity: Vector3,
		world_angular_velocity: Vector3, height_agl: float) -> void:
	position = body_transform.origin
	basis = body_transform.basis
	velocity = world_velocity
	# La base es ortonormal, así que la transpuesta es la inversa y ahorra el
	# determinante de `Basis.inverse()`.
	angular_velocity = basis.transposed() * world_angular_velocity
	var angles := basis.get_euler(EULER_ORDER_YXZ)
	euler = Vector3(-angles.z, angles.x, angles.y)
	altitude_agl = height_agl


## Velocidad lineal en ejes del cuerpo, en m/s.
func body_velocity() -> Vector3:
	return basis.transposed() * velocity


## Velocidades angulares en la convención de piloto de `docs/03` §3.5, en rad/s:
## `x` alabeo, `y` cabeceo, `z` guiñada. Es lo que compara el lazo de tasa de
## WP-05 contra la salida de [ControlProfile].
func rates() -> Vector3:
	return Vector3(-angular_velocity.z, angular_velocity.x, angular_velocity.y)


## Vector unitario que apunta adelante (`−Z` del cuerpo) en coordenadas de mundo.
func forward() -> Vector3:
	return -basis.z


## Vector unitario que apunta arriba (`+Y` del cuerpo) en coordenadas de mundo.
func up() -> Vector3:
	return basis.y


## `true` si el dron está boca abajo, que es la condición de entrada a TURTLE
## (`docs/03` §3.2).
func is_upside_down() -> bool:
	return basis.y.dot(Vector3.UP) < 0.0


## Velocidad respecto del suelo sobre el plano horizontal, en m/s.
func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Devuelve una copia independiente, para quien necesite guardar la lectura más
## allá del sub-paso actual.
func copy() -> FlightState:
	var clone := FlightState.new()
	clone.position = position
	clone.basis = basis
	clone.velocity = velocity
	clone.angular_velocity = angular_velocity
	clone.euler = euler
	clone.altitude_agl = altitude_agl
	return clone


## `true` si ningún componente es `NAN` ni `INF`. Lo usa `flight_bench` para
## detectar que el integrador se fue de rango (`docs/03` §11.7).
func is_finite_state() -> bool:
	return _finite(position) and _finite(velocity) and _finite(angular_velocity) \
			and _finite(euler) and is_finite(altitude_agl)


func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _to_string() -> String:
	return "FlightState(pos %s, v %.2f m/s, agl %.2f m)" \
			% [str(position), velocity.length(), altitude_agl]
