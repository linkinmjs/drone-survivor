## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Una instancia reutilizable del efecto de impacto (`docs/08` §2.10).
##
## No se instancia nada en caliente: [ImpactFXPool] preasigna dieciséis de estas y
## las recicla. Por eso el nodo no se libera nunca; se apaga con [method stop] y se
## vuelve a encender con [method play].
##
## La **variante** (`metal`, `concrete`, `ground`, `debris`) no es una escena por
## material sino un color y una escala aplicados sobre el mismo
## [ParticleProcessMaterial]: cuatro escenas idénticas salvo un tinte serían cuatro
## mallas, cuatro materiales y cuatro veces el mismo código.
##
## El `Decal` **no vive acá**: su vida son 8 s y la de las chispas 0.35 s, así que
## reciclar la instancia entera borraría marcas todavía frescas. Los 32 decals son
## un pool aparte dentro de [ImpactFXPool] (`docs/08` §2.10 los cuenta por separado
## justamente por eso).
class_name ImpactFX extends Node3D

## Variantes de superficie. El índice es el que devuelve
## [method ImpactFXPool.variant_for_layer].
enum Variant {
	METAL,    ## Capa 3: blindaje enemigo; chispas blancas y rápidas.
	WEAK,     ## Capa 4: punto débil; chispas **cian** y destello.
	CONCRETE, ## Capa 8: ciudad; polvo gris, poca chispa.
	GROUND,   ## Capa 1: mundo; tierra y esquirlas.
	DEBRIS,   ## Capa 9: escombro; astillas cortas.
}

## Partículas por impacto (`docs/08` §2.10).
const PARTICLE_AMOUNT: int = 16

## Vida de las partículas, en segundos.
const PARTICLE_LIFETIME: float = 0.35

## Bus de audio del arma (`docs/04` §3.2).
const BUS: StringName = &"Weapons"

## Color de las chispas de cada variante, en el orden de [enum Variant].
##
## **WP-26**: la variante `WEAK` pasa de ámbar `(1.00, 0.68, 0.22)` a **cian**
## `TARGET` (#38E1FF, `docs/13` §2.2). La regla de identidad de `docs/13` §1 es
## que nada enemigo es cálido, y el punto débil es del enemigo: con el ámbar
## viejo, acertarle a una rodilla se veía igual que acertarle a la coraza y el
## jugador no tenía lectura de «le estoy pegando donde duele».
const VARIANT_COLOR: Array[Color] = [
	Color(0.95, 0.90, 0.78, 1.0),
	Color(0.22, 0.88, 1.00, 1.0),
	Color(0.72, 0.70, 0.66, 1.0),
	Color(0.60, 0.52, 0.42, 1.0),
	Color(0.80, 0.76, 0.70, 1.0),
]

## Velocidad inicial de las chispas de cada variante, en m/s.
const VARIANT_SPEED: Array[float] = [7.0, 9.0, 3.5, 3.0, 4.0]

## Tono del sonido de cada variante.
const VARIANT_PITCH: Array[float] = [1.15, 1.25, 0.85, 0.9, 1.0]

## Alcance del sonido posicional, en metros. `audio_check` rechaza cualquier
## `AudioStreamPlayer3D` con `max_distance` 0.
const SOUND_MAX_DISTANCE: float = 220.0

@onready var _sparks: GPUParticles3D = get_node_or_null(^"Sparks") as GPUParticles3D
@onready var _sound: AudioStreamPlayer3D = get_node_or_null(^"Sound") as AudioStreamPlayer3D

var _process_material: ParticleProcessMaterial = null
var _remaining: float = 0.0


func _ready() -> void:
	set_process(false)
	visible = false
	if _sparks != null:
		_sparks.emitting = false
		_sparks.one_shot = true
		_sparks.explosiveness = 1.0
		_sparks.amount = PARTICLE_AMOUNT
		_sparks.lifetime = PARTICLE_LIFETIME
		_sparks.local_coords = false
		_process_material = _sparks.process_material as ParticleProcessMaterial
	if _sound != null:
		_sound.bus = BUS
		_sound.max_distance = SOUND_MAX_DISTANCE


## Cuenta atrás de la instancia. Es presentación pura, por eso vive en `_process`
## y no en el tick de física.
func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	stop()


## Coloca el efecto, lo tiñe según [param variant] y lo lanza.
##
## [param normal] es la normal de la superficie: las chispas salen a lo largo de
## ella, que es lo que hace que un impacto en un techo escupa hacia abajo.
func play(world_position: Vector3, normal: Vector3, variant: int,
		stream: AudioStream) -> void:
	global_position = world_position
	var axis := normal if normal.length_squared() > 0.0001 else Vector3.UP
	_orient(axis.normalized())
	var index := clampi(variant, 0, VARIANT_COLOR.size() - 1)
	visible = true
	if _process_material != null:
		_process_material.color = VARIANT_COLOR[index]
		_process_material.initial_velocity_min = VARIANT_SPEED[index] * 0.35
		_process_material.initial_velocity_max = VARIANT_SPEED[index]
	if _sparks != null:
		_sparks.restart()
		_sparks.emitting = true
	if _sound != null and stream != null:
		_sound.stream = stream
		_sound.pitch_scale = VARIANT_PITCH[index]
		_sound.play()
	_remaining = PARTICLE_LIFETIME
	set_process(true)


## Apaga el efecto y lo devuelve al reposo.
func stop() -> void:
	set_process(false)
	visible = false
	_remaining = 0.0
	if _sparks != null:
		_sparks.emitting = false


## `true` mientras el efecto está en marcha.
func is_playing() -> bool:
	return _remaining > 0.0


## Alinea el eje `+Z` del nodo con [param axis]: `+Z` local es la dirección de
## emisión por defecto del [ParticleProcessMaterial], así que con esto las chispas
## salen a lo largo de la normal sin tocar el material.
func _orient(axis: Vector3) -> void:
	var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := helper.cross(axis).normalized()
	var up := axis.cross(right).normalized()
	global_basis = Basis(right, up, axis)
