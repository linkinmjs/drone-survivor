## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Un motor sin escobillas con su ESC, modelado como un primer orden asimétrico
## (`docs/03` §2.2).
##
## El nodo vive en la posición física del motor dentro del `Drone` y cuelga de él
## la [DronePropeller] que convierte el régimen en fuerzas. El motor **no** aplica
## nada al cuerpo: solo traduce comando a rpm y publica el par de reacción que el
## integrador suma.
##
## Dinámica: `rpm += (rpm_target − rpm) · (1 − e^(−dt/τ))`, que es la solución
## exacta del primer orden, así que el resultado no depende del tamaño del
## sub-paso. `τ` vale [member tau_up] al acelerar y [member tau_down] al frenar,
## porque un ESC empuja con corriente pero frena solo con el arrastre de la hélice.
##
## Con los valores de fábrica (`docs/03` §10) el motor pasa de ralentí al 90 %
## de [member max_rpm] en **0.0675 s**, dentro del límite de 0.12 s de §11.3.
class_name DroneMotor extends Node3D

## Sentido de giro visto desde arriba: `+1` horario (CW), `−1` antihorario (CCW).
## Es el mismo entero que el metadato `spin` del GLB (`docs/05` §10), de modo que
## el modelo y la física no pueden desincronizarse.
@export_enum("CCW:-1", "CW:1") var spin: int = 1

## Número de motor, 1 a 4, en el orden del mezclador de `docs/03` §3.5:
## 1 delantero-izquierdo, 2 delantero-derecho, 3 trasero-derecho, 4 trasero-izquierdo.
@export_range(1, 4, 1) var motor_index: int = 1

## Régimen máximo en rpm con el comando a fondo (KV 2400 en 4S bajo carga).
@export var max_rpm: float = 30000.0

## Régimen de ralentí en rpm, el que sostiene el motor armado con el acelerador
## al mínimo. Es el `idle` del mezclador llevado a rpm.
@export var idle_rpm: float = 1500.0

## Constante de tiempo al acelerar, en segundos.
@export var tau_up: float = 0.030

## Constante de tiempo al frenar, en segundos.
@export var tau_down: float = 0.060

## Permite comandos negativos (modo TURTLE, `docs/03` §3.2). Apagado, cualquier
## comando negativo se trata como cero.
@export var allow_reverse: bool = false

## Régimen actual en rpm. Negativo significa giro invertido (TURTLE).
var rpm: float = 0.0

## Régimen al que tiende [member rpm]. Lo fija [method set_command].
var rpm_target: float = 0.0

## `false` fuerza [member rpm_target] a cero sin importar el comando: es el
## estado desarmado.
var powered: bool = false

## Último comando recibido, en `[−1, 1]`. Solo informativo.
var command: float = 0.0

## Factor sobre el régimen máximo efectivo, que es como `Drone.set_thrust_scale`
## limita el empuje con energía crítica (`docs/03` §9).
var thrust_scale: float = 1.0

## Fracción del comando negativo que se admite en reversa, con el stick a fondo.
##
## Discrepancia registrada con `docs/03` §2.2 — **cuánta reversa hace falta para
## dar vuelta el dron**. §2.2 fija el tope en `−0.5 · max_rpm`, y con ese valor
## TURTLE (§3.2) **no funciona**, medido en `flight_check`: a 15 000 rpm cada
## hélice invertida da `0.5 · C_T · ρ · n² · D⁴ = 1.18 N`, o sea 2.37 N entre los
## dos motores de un lado; apoyado boca abajo sobre las cuatro esferas de motor,
## el par de vuelco respecto de la línea de apoyo opuesta vale `2.37 · 0.17 =
## 0.40 N·m` contra los `m·g · 0.085 = 0.58 N·m` que hace la gravedad. Faltaba un
## 31 %: el dron ni se movía en 3.5 s (`y · UP` clavado en −1.000).
##
## El mínimo teórico para que empiece a volcarse es **0.602**. Se elige **0.75**,
## que deja un margen de 1.55× (2.67 N por motor, 0.91 N·m de par) y sigue por
## debajo del peso —5.33 N contra 6.87 N—, así que el dron gira sobre su apoyo en
## vez de pegar un salto. No se toca [constant DronePropeller.REVERSE_EFFICIENCY],
## que sí queda en la mitad que pide §2.2: el empuje en reversa sigue valiendo la
## mitad del directo al mismo régimen. Lo que sube es **hasta qué régimen deja
## llegar el ESC en reversa**, que en Betaflight es un parámetro de configuración,
## no una constante física.
const REVERSE_LIMIT: float = 0.75

## Hélice que cuelga de este motor. Se resuelve en [method _ready] y puede ser
## `null` en una escena de prueba sin hélices.
var propeller: DronePropeller = null


func _ready() -> void:
	propeller = get_node_or_null(^"Propeller") as DronePropeller


## Traduce un comando del mezclador a [member rpm_target].
##
## [param cmd] va en `[0, 1]`; con [member allow_reverse] activo admite hasta
## `−1`, que corresponde a `−0.5 · max_rpm`. Desarmado el objetivo es siempre 0.
func set_command(cmd: float) -> void:
	command = clampf(cmd, -1.0 if allow_reverse else 0.0, 1.0)
	if not powered:
		rpm_target = 0.0
		return
	rpm_target = rpm_for_command(command)


## Mapa puro de comando a régimen, sin tocar el estado del motor. Lo usa el
## mezclador para previsualizar y `flight_bench` para la bisección del hover.
func rpm_for_command(cmd: float) -> float:
	var limit := effective_max_rpm()
	if cmd < 0.0:
		if not allow_reverse:
			return idle_rpm
		return maxf(cmd, -1.0) * REVERSE_LIMIT * limit
	return idle_rpm + clampf(cmd, 0.0, 1.0) * maxf(limit - idle_rpm, 0.0)


## Avanza la dinámica del motor [param dt] segundos.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	# Acelerar y frenar no cuestan lo mismo: el ESC inyecta corriente para subir
	# de régimen, pero para bajar solo puede dejar de empujar (`docs/03` §2.2).
	var tau := tau_up if absf(rpm_target) >= absf(rpm) else tau_down
	if tau <= 0.0:
		rpm = rpm_target
		return
	rpm += (rpm_target - rpm) * (1.0 - exp(-dt / tau))
	if absf(rpm) < 1e-3:
		rpm = 0.0


## Par de reacción que este motor imprime al cuerpo alrededor de su eje `+Y`,
## en N·m (`docs/03` §2.2).
##
## Una hélice que gira CW vista desde arriba arrastra el aire en ese sentido y,
## por tercera ley, empuja el cuerpo en el contrario, que en ejes de Godot es
## rotación **positiva** sobre `+Y` (morro a la izquierda). Por eso el signo es
## `+spin`, no `−spin`: ver la nota de discrepancia en `drone.gd`.
func get_torque() -> float:
	if propeller == null or is_zero_approx(rpm):
		return 0.0
	return float(spin) * signf(rpm) * propeller.static_torque(rpm)


## Régimen máximo realmente disponible, ya escalado por [member thrust_scale].
func effective_max_rpm() -> float:
	return max_rpm * maxf(thrust_scale, 0.0)


## Régimen actual como fracción de [member max_rpm], en `[−1, 1]`. Lo consumen el
## audio de motores (`docs/03` §6) y el desenfoque de hélices.
func rpm_ratio() -> float:
	if max_rpm <= 0.0:
		return 0.0
	return clampf(rpm / max_rpm, -1.0, 1.0)


## Enciende el motor y lo deja en ralentí. Lo llama `Drone.arm()`.
func spin_up_to_idle() -> void:
	powered = true
	set_command(0.0)


## Apaga el motor: el objetivo cae a cero y la hélice se frena con `tau_down`.
func shut_down() -> void:
	powered = false
	command = 0.0
	rpm_target = 0.0


## Deja el motor completamente parado y sin comando, sin transición. Lo llama
## `Drone.reset_to()`.
func reset() -> void:
	shut_down()
	rpm = 0.0
