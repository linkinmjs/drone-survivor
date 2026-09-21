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
## **WP-26**: el pulso pasa de 40 a **60 ms** y la energía de 3.5 a **4.0**, que es
## lo que fija `docs/13` §4 («OmniLight3D de 3 m, energía 4→0 en 0.06 s»); se cierra
## así la discrepancia que WP-14 había registrado contra `docs/08` §2.10. Se suma
## además el **quad emisivo** de la llamarada, que aparece con la luz y se encoge
## con ella: es lo que le da forma al fogonazo delante del cañón.
##
## **Legibilidad (checkpoint 4)**: la energía baja a **1.5** y el alcance a **2 m**.
## El grueso del ajuste no está acá sino en la escena (chispas más chicas, más
## juntas y por debajo del umbral de glow): el desglose medido está en el
## encabezado de `muzzle_flash.tscn`.
##
## El efecto es de este nodo y **no** del [VFXPool] a propósito: §4 lo declara «1
## emisor permanente» que no cuenta contra el presupuesto, y a 8 disparos por
## segundo pedirle una instancia al pool en cada tiro sería el único cliente capaz
## de vaciarlo solo. El pool lo registra igual con esta ruta, para que un showcase
## pueda pedirlo suelto.
class_name MuzzleFlash extends Node3D

## Duración total del pulso de luz, en segundos (`docs/13` §4).
const PULSE_SECONDS: float = 0.06

## Energía máxima de la luz durante el pulso.
##
## `docs/13` §4 pedía **4.0**. Baja a 1.5 por el ajuste de legibilidad del
## checkpoint 4 («los disparos dificultan un poco la visión»): con `omni_range`
## en 2 m y la exposición de WP-24, una luz de energía 4 a 0.35 m de la cámara
## aporta un velo cálido sobre el centro del cuadro. Medida la ablación, no era
## la pieza dominante —lo eran las chispas, ver `muzzle_flash.tscn`— pero sí
## suma: apagarla del todo bajaba el velo de +20.2 % a +18.5 %.
const PULSE_ENERGY: float = 1.5

## Fracción del pulso que dura la subida.
const PULSE_ATTACK: float = 0.25

## Escala mínima del quad de llamarada al final del pulso.
const BLOOM_MIN_SCALE: float = 0.35

@onready var _particles: GPUParticles3D = get_node_or_null(^"Particles") as GPUParticles3D
@onready var _light: OmniLight3D = get_node_or_null(^"FlashLight") as OmniLight3D
@onready var _bloom: MeshInstance3D = get_node_or_null(^"Bloom") as MeshInstance3D

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
	if _bloom != null:
		_bloom.visible = false


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
		if _bloom != null:
			_bloom.visible = false
		set_process(false)
		return
	# Subida rápida y caída larga: es como se ve un fogonazo real en vídeo.
	var energy := t / PULSE_ATTACK if t < PULSE_ATTACK \
			else 1.0 - (t - PULSE_ATTACK) / (1.0 - PULSE_ATTACK)
	energy = clampf(energy, 0.0, 1.0)
	if _light != null:
		_light.light_energy = PULSE_ENERGY * energy
	if _bloom != null:
		# La llamarada nace chica y crece con la luz, y se va con ella.
		var bloom_scale := lerpf(BLOOM_MIN_SCALE, 1.0, energy)
		_bloom.scale = Vector3(bloom_scale, bloom_scale, bloom_scale)


## Relanza el destello. Es idempotente dentro del mismo frame.
func flash() -> void:
	if _particles != null:
		_particles.restart()
		_particles.emitting = true
	_elapsed = 0.0
	if _light != null:
		_light.visible = true
		_light.light_energy = 0.0
	if _bloom != null:
		_bloom.visible = true
		_bloom.scale = Vector3(BLOOM_MIN_SCALE, BLOOM_MIN_SCALE, BLOOM_MIN_SCALE)
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
	if _bloom != null:
		_bloom.visible = false


## `true` mientras el pulso de luz está corriendo.
func is_flashing() -> bool:
	return _elapsed >= 0.0


## Alias de [method flash] con la firma que usa [VFXPool] para todo efecto. El
## parámetro de escala no aplica: el fogonazo es siempre el mismo.
func play(_scale: float = 1.0) -> void:
	flash()


## Alias de [method is_flashing] con el nombre del contrato del pool.
func is_playing() -> bool:
	return is_flashing()
