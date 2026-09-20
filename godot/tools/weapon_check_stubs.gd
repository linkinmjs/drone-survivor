## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Dobles de prueba de `weapon_check` (`docs/08` §5).
##
## Los tres sistemas contra los que dispara el arma —`EnemyPart` (`docs/06`),
## `Building` (`docs/10`) y `EnergySystem` (`docs/09`)— **todavía no existen**:
## son WP-16, WP-20 y WP-15. El arma se acopla a ellos por metadatos y por duck
## typing, así que lo que hay que probar es justamente que el contrato mínimo
## alcanza. Estos dobles implementan ese contrato y nada más, y registran lo que
## reciben para que el check pueda afirmar sobre ello.
##
## Van en un archivo de clases internas y no en tres scripts sueltos porque son
## datos de una sola prueba: ninguno tiene `class_name` y ninguno viaja en la build
## (`tools/` está excluido del export, `docs/02` §8).
class_name WeaponCheckStubs extends RefCounted


## Parte enemiga de prueba: el contrato de `EnemyPart` de `docs/06` §14.
##
## Es un [AnimatableBody3D], como las partes reales, y aplica el **blindaje** —y
## sólo el blindaje—: el multiplicador de punto débil lo aplica el arma
## (`docs/08` §2.7, la regla que no se puede invertir). Con `armor` 0.90 un
## impacto de 12 deja 1.2 de daño efectivo; con `armor` 0.0 un impacto de 36 deja
## 36.
class PartStub extends AnimatableBody3D:
	## Fracción del daño que absorbe el blindaje, de 0.0 a 1.0.
	var armor: float = 0.90

	## Estructura restante.
	var hp: float = 10000.0

	## Impactos recibidos.
	var hits: int = 0

	## Daño **bruto** del último impacto, el que pasó el arma.
	var last_amount: float = -1.0

	## Daño **efectivo** del último impacto, el que devolvió [method take_damage].
	var last_effective: float = -1.0

	## Copia del último diccionario `hit` recibido.
	var last_hit: Dictionary = {}

	## Contrato de `docs/06` §14.1: devuelve el daño efectivo y **no escribe nada**
	## dentro de [param hit].
	func take_damage(amount: float, hit: Dictionary) -> float:
		hits += 1
		last_amount = amount
		last_hit = hit.duplicate()
		var effective := amount * (1.0 - clampf(armor, 0.0, 1.0))
		hp = maxf(hp - effective, 0.0)
		last_effective = effective
		return effective

	## `hp <= 0`, igual que `EnemyPart` (`docs/06` §5).
	func is_broken() -> bool:
		return hp <= 0.0

	## Deja el doble como recién creado.
	func reset() -> void:
		hits = 0
		last_amount = -1.0
		last_effective = -1.0
		last_hit = {}


## Edificio de prueba: el contrato de `Building.take_damage(amount, point)` de
## `docs/10` §5. No devuelve nada a propósito, para comprobar que el resolvedor
## aguanta un duck type que no respeta ninguna convención de retorno.
class BuildingStub extends StaticBody3D:
	## Daño estructural acumulado.
	var damage_taken: float = 0.0

	## Impactos recibidos.
	var hits: int = 0

	## Daño del último impacto.
	var last_amount: float = -1.0

	## Punto del último impacto.
	var last_point: Vector3 = Vector3.ZERO

	func take_damage(amount: float, point: Vector3) -> void:
		hits += 1
		last_amount = amount
		last_point = point
		damage_taken += amount

	func reset() -> void:
		hits = 0
		damage_taken = 0.0
		last_amount = -1.0


## Sistema de energía de prueba: el contrato de `EnergySystem.consume(amount) -> bool`
## de `docs/09` §2. Con [member allow] en `false` rechaza el cobro, que es lo que
## el sub-check 11 necesita para comprobar que un cobro rechazado **no consume
## nada** y **no deja salir el disparo**.
class EnergyStub extends Node:
	## Si es `false`, [method consume] rechaza siempre.
	var allow: bool = true

	## Energía cobrada de verdad.
	var consumed: float = 0.0

	## Llamadas recibidas, aceptadas o no.
	var calls: int = 0

	func consume(amount: float) -> bool:
		calls += 1
		if not allow:
			return false
		consumed += amount
		return true

	func reset() -> void:
		calls = 0
		consumed = 0.0
