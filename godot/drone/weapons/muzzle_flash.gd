## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Destello de boca del arma primaria (`docs/08` §2.10).
##
## Uno solo, hijo del [WeaponMount], relanzado con `restart()` en cada disparo: a
## 0.125 s de intervalo y 0.08 s de vida de partícula no hay solape posible, así
## que no hace falta pool.
##
## El pulso de la luz se hace con un **acumulador en `_process`**, no con un
## [Tween]. La regla del proyecto sólo admite temporizadores de nodo para
## presentación, y un `Tween` acá lo sería, pero un acumulador de tres líneas
## evita el `kill()` antes de recrear que `docs/08` §2.10 tiene que prescribir
## justamente porque un `Tween` sobreviviente pisaría el pulso siguiente.
##
## Discrepancia registrada con `docs/08` §2.10: el pulso dura
## [constant PULSE_SECONDS] = **40 ms** (el valor del brief de WP-14), no los 60 ms
## del documento. El perfil de subida y bajada es el mismo, 0 → pico → 0.
class_name MuzzleFlash extends Node3D

## Duración total del pulso de luz, en segundos.
const PULSE_SECONDS: float = 0.04

## Energía máxima de la luz durante el pulso.
const PULSE_ENERGY: float = 3.5

## Fracción del pulso que dura la subida.
const PULSE_ATTACK: float = 0.25

@onready var _particles: GPUParticles3D = get_node_or_null(^"Particles") as GPUParticles3D
@onready var _light: OmniLight3D = get_node_or_null(^"FlashLight") as OmniLight3D

var _elapsed: float = -1.0


func _ready() -> void:
	set_process(false)
	if _particles != null:
		_particles.emitting = false
		_particles.one_shot = true
		_particles.explosiveness = 1.0
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		set_process(false)
		return
	_elapsed += delta
	var t := _elapsed / PULSE_SECONDS
	if t >= 1.0:
		_elapsed = -1.0
		if _light != null:
			_light.light_energy = 0.0
			_light.visible = false
		set_process(false)
		return
	if _light == null:
		return
	# Subida rápida y caída larga: es como se ve un fogonazo real en vídeo.
	var energy := t / PULSE_ATTACK if t < PULSE_ATTACK \
			else 1.0 - (t - PULSE_ATTACK) / (1.0 - PULSE_ATTACK)
	_light.light_energy = PULSE_ENERGY * clampf(energy, 0.0, 1.0)


## Relanza el destello. Es idempotente dentro del mismo frame.
func flash() -> void:
	if _particles != null:
		_particles.restart()
		_particles.emitting = true
	_elapsed = 0.0
	if _light != null:
		_light.visible = true
		_light.light_energy = 0.0
	set_process(true)


## Apaga el destello de inmediato (respawn, pausa, checks).
func stop() -> void:
	_elapsed = -1.0
	set_process(false)
	if _particles != null:
		_particles.emitting = false
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false


## `true` mientras el pulso de luz está corriendo.
func is_flashing() -> bool:
	return _elapsed >= 0.0
