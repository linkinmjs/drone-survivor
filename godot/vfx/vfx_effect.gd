## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Raíz común de todos los efectos de `vfx/` (`docs/13` §4).
##
## Un efecto es una escena con un puñado de nodos de presentación —
## [GPUParticles3D], [OmniLight3D], [Decal], [FogVolume], [MeshInstance3D]— y
## **ningún** estado de juego. Este script hace las cuatro cosas que todos
## necesitan y que si no habría que repetir en diecisiete lugares:
##
## 1. **Impone el contrato de `docs/13` §4** sobre cada [GPUParticles3D] al
##    entrar al árbol: `one_shot`, `explosiveness = 1`, `fixed_fps = 30`,
##    `interpolate`, `draw_order = DRAW_ORDER_VIEW_DEPTH` y `gi_mode = DISABLED`.
##    Así ninguna escena se desvía del documento por un olvido de edición, y
##    `vfx_check` puede aseverarlo sobre el pool entero.
## 2. **Cablea las texturas procedurales** de [VFXTextures] a los materiales que
##    las pidan por el metadato `vfx_texture`. Un `.tscn` no puede guardar una
##    textura generada en código, así que la referencia va por nombre.
## 3. **Cuenta atrás y apagado**, con acumulador en `_process` y nunca un
##    [Timer] (convención de `docs/00` §6). Las luces bajan su energía, los
##    decals su `modulate.a` y las nieblas su densidad.
## 4. **Seguimiento**: un efecto puede quedar pegado a un nodo que se mueve —el
##    [DebrisChunk] de una parte desprendida, la parte dañada que echa chispas—
##    sin reparentarse, que reventaría el reciclado del pool.
##
## El dueño de la vida es siempre [VFXPool]: [method play] devuelve el efecto
## encendido y el pool lo suelta cuando [method is_playing] da `false` o cuando
## alguien llama a `release()`.
class_name VFXEffect extends Node3D

## Metadato que declara qué textura de [VFXTextures] quiere un material.
const META_TEXTURE: StringName = &"vfx_texture"

## Metadato que marca un [GPUParticles3D] que emite en bucle en vez de una sola
## vez (las chispas de parte dañada, el humo del derrumbe, el halo de la pila).
const META_CONTINUOUS: StringName = &"vfx_continuous"

## Metadato que pide que un [Decal] use su textura también como **emisión**.
##
## Un decal normal reemplaza el albedo y queda a merced de la luz que haya: sobre
## el asfalto de una calle al anochecer, una marca de aviso se ve gris. Con la
## emisión encendida el aviso brilla por su cuenta y cruza el umbral de glow de
## 1.4 (WP-24), que es lo que una señal de peligro necesita. Sólo lo piden las
## telegrafías; una cicatriz —el cráter, una quemadura— no brilla.
const META_EMISSIVE: StringName = &"vfx_emissive"

## Fotogramas por segundo de todo sistema de partículas (`docs/13` §4).
const PARTICLE_FPS: int = 30

## Vida por defecto del efecto, en segundos. `0` significa «hasta que lo suelten»
## y es lo que usan los haces y las telegrafías, cuya duración la manda el ataque.
@export var life_seconds: float = 1.0

## Segundos que tarda la luz del efecto en caer de su energía nominal a cero.
@export var light_fade_seconds: float = 0.06

## Segundos que vive el [Decal] del efecto, contados aparte de [member
## life_seconds] porque una marca dura mucho más que sus chispas.
@export var decal_seconds: float = 0.0

## Fracción final de la vida del decal durante la que se desvanece.
@export_range(0.0, 1.0, 0.01) var decal_fade_fraction: float = 0.35

var _particles: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _light_energy: PackedFloat32Array = PackedFloat32Array()
var _decals: Array[Decal] = []
var _fog: Array[FogVolume] = []
var _fog_density: PackedFloat32Array = PackedFloat32Array()

var _age: float = 0.0
var _decal_age: float = -1.0
var _tail: float = 0.0
var _playing: bool = false
var _follow: Node3D = null
var _follow_offset: Vector3 = Vector3.ZERO
var _amount_scale: float = 1.0


func _ready() -> void:
	_collect()
	_enforce_contract()
	_wire_textures()
	stop()


## Cuenta atrás, desvanecidos y seguimiento. Presentación pura, por eso vive en
## `_process` y no en el tick de física.
func _process(delta: float) -> void:
	if _follow != null:
		if is_instance_valid(_follow):
			global_position = _follow.global_position + _follow_offset
		else:
			_follow = null
	_age += delta
	_fade_lights()
	_fade_fog()
	_age_decals(delta)
	if _playing and life_seconds > 0.0 and _age >= life_seconds:
		_playing = false
		# La cola es lo que las partículas ya emitidas tardan en morir. Sin ella
		# el pool recicla la instancia en el instante en que deja de emitir y la
		# columna de polvo de un derrumbe se corta a cuchillo a los 3 s.
		_tail = _tail_seconds()
		_on_expired()
	elif _tail > 0.0:
		_tail = maxf(0.0, _tail - delta)
	if not is_playing():
		set_process(false)


# --------------------------------------------------------------------------
# Interfaz que consume `VFXPool`
# --------------------------------------------------------------------------

## Enciende el efecto. [param scale] escala la cantidad de partículas de 0 a 1:
## es lo que hace que una pisada suave levante menos polvo que un pisotón.
func play(scale: float = 1.0) -> void:
	_age = 0.0
	_tail = 0.0
	_amount_scale = clampf(scale, 0.05, 1.0)
	_playing = true
	visible = true
	for particles: GPUParticles3D in _particles:
		particles.amount_ratio = _amount_scale
		particles.restart()
		particles.emitting = true
	for index: int in _lights.size():
		_lights[index].light_energy = _light_energy[index]
		_lights[index].visible = true
	for index: int in _fog.size():
		_fog[index].material.set(&"density", _fog_density[index])
		_fog[index].visible = true
	if decal_seconds > 0.0 and not _decals.is_empty():
		_decal_age = 0.0
		for decal: Decal in _decals:
			decal.modulate.a = 1.0
			decal.visible = true
	_on_play()
	set_process(true)


## Apaga el efecto y lo deja listo para volver al pool. Es idempotente.
func stop() -> void:
	_playing = false
	_age = 0.0
	_tail = 0.0
	_decal_age = -1.0
	_follow = null
	_follow_offset = Vector3.ZERO
	visible = false
	for particles: GPUParticles3D in _particles:
		particles.emitting = false
	for index: int in _lights.size():
		_lights[index].light_energy = 0.0
		_lights[index].visible = false
	for index: int in _fog.size():
		_fog[index].visible = false
	for decal: Decal in _decals:
		decal.visible = false
	_on_stop()
	set_process(false)


## `true` mientras el efecto tenga algo que mostrar: emitiendo, con partículas
## todavía vivas o con un decal sin desvanecer. El pool no recicla la instancia
## hasta que da `false`.
func is_playing() -> bool:
	return _playing or _tail > 0.0 or _decal_age >= 0.0


## Segundos que las partículas ya emitidas tardan en morir después de que el
## efecto deje de emitir. Un `one_shot` lanza todo en el instante 0, así que su
## cola es lo que le sobre a la vida de la partícula sobre la del efecto; un
## emisor continuo emite hasta el final y su cola es la vida entera.
func _tail_seconds() -> float:
	var tail := 0.0
	for particles: GPUParticles3D in _particles:
		var span := _particle_span(particles)
		var own: float = span - life_seconds if particles.one_shot else span
		tail = maxf(tail, own)
	return maxf(tail, 0.0)


## Vida máxima de una partícula de [param particles], con su aleatoriedad.
##
## `lifetime_randomness` es del [ParticleProcessMaterial] y **no** del
## [GPUParticles3D] —el nodo tiene `randomness`, que es otra cosa: la dispersión
## del instante de emisión—, así que hay que ir a buscarla al material.
func _particle_span(particles: GPUParticles3D) -> float:
	var material := particles.process_material as ParticleProcessMaterial
	var randomness := material.lifetime_randomness if material != null else 0.0
	return particles.lifetime * (1.0 + randomness)


## Pega el efecto a [param target]: en cada frame se coloca donde esté el nodo,
## más el desplazamiento que tenía al empezar a seguirlo.
func follow(target: Node3D) -> void:
	_follow = target
	if target == null or not is_instance_valid(target):
		_follow = null
		_follow_offset = Vector3.ZERO
		return
	_follow_offset = global_position - target.global_position


## Deja de seguir al nodo, congelando el efecto donde esté.
func unfollow() -> void:
	_follow = null


## Tiñe todo lo que el efecto pueda teñir: proceso de partículas, luces y decals.
## Lo usan el pool y las acciones para pasar del cian del enemigo al rojo de
## peligro sin duplicar escenas.
func set_color(color: Color) -> void:
	for particles: GPUParticles3D in _particles:
		var material := particles.process_material as ParticleProcessMaterial
		if material != null:
			material.color = color
	for light: OmniLight3D in _lights:
		light.light_color = color
	for decal: Decal in _decals:
		decal.modulate = Color(color.r, color.g, color.b, decal.modulate.a)


## Sistemas de partículas del efecto. Lo consume [VFXPool] para contar emisores
## y `vfx_check` para aseverar el contrato de §4.
func particle_systems() -> Array[GPUParticles3D]:
	return _particles


## Emisores que están emitiendo **de verdad** ahora mismo.
func emitting_count() -> int:
	var count := 0
	for particles: GPUParticles3D in _particles:
		if particles.emitting:
			count += 1
	return count


## Vida más larga de las partículas del efecto, en segundos. `vfx_check` la usa
## para saber cuándo un `emitting = true` ya es una fuga.
func longest_particle_life() -> float:
	var longest := 0.0
	for particles: GPUParticles3D in _particles:
		longest = maxf(longest, _particle_span(particles))
	return longest


# --------------------------------------------------------------------------
# Ganchos de las subclases
# --------------------------------------------------------------------------

## Se llama al final de [method play].
func _on_play() -> void:
	pass


## Se llama al final de [method stop].
func _on_stop() -> void:
	pass


## Se llama cuando se acaba [member life_seconds]. Por defecto apaga las
## partículas pero deja vivo el decal, que dura más.
func _on_expired() -> void:
	for particles: GPUParticles3D in _particles:
		particles.emitting = false
	for light: OmniLight3D in _lights:
		light.visible = false


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Junta los nodos de presentación de todo el subárbol, una sola vez.
func _collect() -> void:
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var particles := node as GPUParticles3D
		if particles != null:
			_particles.append(particles)
			continue
		var light := node as OmniLight3D
		if light != null:
			_lights.append(light)
			_light_energy.append(light.light_energy)
			continue
		var decal := node as Decal
		if decal != null:
			_decals.append(decal)
			continue
		var fog := node as FogVolume
		if fog != null and fog.material != null:
			# El `FogMaterial` es un sub-recurso de la escena y **se comparte**
			# entre las instancias que el pool preasigna: desvanecer una apagaría
			# la niebla de las otras. Cada instancia se queda con su copia.
			fog.material = fog.material.duplicate()
			_fog.append(fog)
			_fog_density.append(float(fog.material.get(&"density")))


## Impone la tabla de `docs/13` §4 sobre cada sistema de partículas.
func _enforce_contract() -> void:
	for particles: GPUParticles3D in _particles:
		var continuous := particles.has_meta(META_CONTINUOUS) \
				and bool(particles.get_meta(META_CONTINUOUS))
		particles.one_shot = not continuous
		if not continuous:
			particles.explosiveness = 1.0
		particles.fixed_fps = PARTICLE_FPS
		particles.interpolate = true
		particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.emitting = false


## Conecta las texturas de [VFXTextures] a quien las pida por metadato.
func _wire_textures() -> void:
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node.has_meta(META_TEXTURE):
			continue
		var texture := _texture_named(StringName(node.get_meta(META_TEXTURE)))
		if texture == null:
			continue
		var decal := node as Decal
		if decal != null:
			decal.texture_albedo = texture
			if decal.has_meta(META_EMISSIVE) and bool(decal.get_meta(META_EMISSIVE)):
				decal.texture_emission = texture
			continue
		var particles := node as GPUParticles3D
		if particles != null:
			_set_pass_texture(particles, texture)
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			var material := _mesh_material(mesh_instance) as BaseMaterial3D
			if material != null:
				material.albedo_texture = texture


## Textura de [VFXTextures] por nombre.
func _texture_named(key: StringName) -> Texture2D:
	match key:
		&"spark":
			return VFXTextures.spark()
		&"dust":
			return VFXTextures.dust()
		&"smoke":
			return VFXTextures.smoke()
		&"shard":
			return VFXTextures.shard()
		&"burn":
			return VFXTextures.burn()
		&"zone_ring":
			return VFXTextures.zone_ring()
		&"crater":
			return VFXTextures.crater()
		&"halo":
			return VFXTextures.halo()
	push_warning("VFXEffect: textura procedural desconocida '%s'." % String(key))
	return null


## Pone [param texture] en el material de la primera pasada de dibujo.
func _set_pass_texture(particles: GPUParticles3D, texture: Texture2D) -> void:
	var mesh := particles.draw_pass_1
	if mesh == null:
		return
	# En un [PrimitiveMesh] —que es lo que dibujan todas estas escenas—
	# `surface_get_material(0)` devuelve su propiedad `material`.
	var material := mesh.surface_get_material(0) as BaseMaterial3D
	if material != null:
		material.albedo_texture = texture


## Material efectivo de una malla: el `material_override`, el de la superficie 0
## o el del recurso de malla.
func _mesh_material(mesh_instance: MeshInstance3D) -> Material:
	if mesh_instance.material_override != null:
		return mesh_instance.material_override
	if mesh_instance.mesh == null:
		return null
	var surface := mesh_instance.get_surface_override_material(0)
	if surface != null:
		return surface
	return mesh_instance.mesh.surface_get_material(0)


## Baja la energía de las luces en [member light_fade_seconds].
func _fade_lights() -> void:
	if _lights.is_empty() or light_fade_seconds <= 0.0:
		return
	var ratio := clampf(1.0 - _age / light_fade_seconds, 0.0, 1.0)
	for index: int in _lights.size():
		var light := _lights[index]
		light.light_energy = _light_energy[index] * ratio
		if ratio <= 0.0 and light.visible:
			light.visible = false


## La niebla se va con la vida del efecto, no con la de la luz: es lo que queda
## flotando después del golpe.
func _fade_fog() -> void:
	if _fog.is_empty() or life_seconds <= 0.0:
		return
	var ratio := clampf(1.0 - _age / life_seconds, 0.0, 1.0)
	for index: int in _fog.size():
		_fog[index].material.set(&"density", _fog_density[index] * ratio * ratio)


## Envejece el decal, que vive su propia cuenta y se desvanece al final.
func _age_decals(delta: float) -> void:
	if _decal_age < 0.0 or _decals.is_empty():
		return
	_decal_age += delta
	if _decal_age >= decal_seconds:
		_decal_age = -1.0
		for decal: Decal in _decals:
			decal.visible = false
		return
	var fade_start := decal_seconds * (1.0 - decal_fade_fraction)
	if _decal_age <= fade_start:
		return
	var alpha := clampf(1.0 - (_decal_age - fade_start)
			/ maxf(decal_seconds - fade_start, 0.0001), 0.0, 1.0)
	for decal: Decal in _decals:
		decal.modulate.a = alpha
