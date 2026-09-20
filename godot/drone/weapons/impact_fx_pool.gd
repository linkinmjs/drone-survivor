## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pool de efectos de impacto y de marcas de bala (`docs/08` §2.10).
##
## **Dos pools, no uno**, porque las dos cosas duran distinto: dieciséis
## [ImpactFX] de 0.35 s para las chispas y el sonido, y treinta y dos [Decal] de
## 8 s para las marcas. Reciclar la instancia entera al terminar las chispas
## borraría marcas recién puestas; tenerlas juntas obligaría a dieciséis instancias
## de ocho segundos, o sea a perder el efecto a la cuarta ráfaga.
##
## Los dos pools reciclan **el más viejo** cuando se quedan sin ranuras, que es lo
## correcto para presentación: la marca que se pierde es la que menos se nota.
##
## `Decal` sólo en las capas 1 (`world`) y 8 (`city`): el blindaje enemigo y los
## escombros se mueven, y una calcomanía proyectada sobre un cuerpo animado se
## despega del impacto en el frame siguiente.
##
## Se instala en el nivel y se busca por el grupo [constant GROUP]; si no hay
## ninguno, [ProjectilePool] crea el suyo (ver la nota de instalación de
## `projectile_pool.gd`).
class_name ImpactFXPool extends Node3D

## Grupo por el que lo encuentra [ProjectilePool].
const GROUP: StringName = &"impact_fx_pool"

## Instancias de [ImpactFX] preasignadas (`docs/08` §2.10).
const FX_COUNT: int = 16

## Decals simultáneos como máximo.
const DECAL_COUNT: int = 32

## Vida de un decal, en segundos.
const DECAL_LIFETIME: float = 8.0

## Fracción final de la vida durante la que el decal se desvanece.
const DECAL_FADE_FRACTION: float = 0.25

## Lado del decal, en metros.
const DECAL_SIZE: float = 0.8

## Distancia a la que el decal empieza a desaparecer, en metros.
const DECAL_FADE_BEGIN: float = 40.0

## Mezcla del albedo del decal con la superficie.
const DECAL_ALBEDO_MIX: float = 0.9

## Ruta de la escena de una instancia del pool.
const FX_SCENE: String = "res://drone/weapons/impact_fx.tscn"

## Escena de [ImpactFX]; si queda vacía se carga [constant FX_SCENE].
@export var fx_scene: PackedScene

## Sonido posicional del impacto. Lo cablea [ProjectilePool] desde el perfil.
@export var impact_sound: AudioStream

var _fx: Array[ImpactFX] = []
var _fx_next: int = 0
var _decals: Array[Decal] = []
var _decal_age: PackedFloat32Array = PackedFloat32Array()
var _decal_next: int = 0
var _decal_requests: int = 0
var _decal_texture: Texture2D = null


func _ready() -> void:
	add_to_group(GROUP)
	_build_fx()
	_build_decals()


## Envejece los decals vivos y los desvanece. Presentación pura: `_process`.
func _process(delta: float) -> void:
	for index: int in _decals.size():
		if _decal_age[index] < 0.0:
			continue
		_decal_age[index] += delta
		var decal := _decals[index]
		if _decal_age[index] >= DECAL_LIFETIME:
			_retire_decal(index)
			continue
		var fade_start := DECAL_LIFETIME * (1.0 - DECAL_FADE_FRACTION)
		if _decal_age[index] <= fade_start:
			decal.modulate.a = 1.0
			continue
		var t := (_decal_age[index] - fade_start) / maxf(DECAL_LIFETIME - fade_start, 0.0001)
		decal.modulate.a = clampf(1.0 - t, 0.0, 1.0)


## Lanza un impacto en [param position] con la normal [param normal] y la variante
## de [enum ImpactFX.Variant] indicada. Devuelve la instancia usada.
func spawn(position: Vector3, normal: Vector3, variant: int) -> ImpactFX:
	if _fx.is_empty():
		return null
	# Sin ranura libre se recicla la más vieja, que es la siguiente del anillo.
	var chosen: ImpactFX = null
	for offset: int in _fx.size():
		var index := (_fx_next + offset) % _fx.size()
		if not _fx[index].is_playing():
			chosen = _fx[index]
			_fx_next = (index + 1) % _fx.size()
			break
	if chosen == null:
		chosen = _fx[_fx_next]
		chosen.stop()
		_fx_next = (_fx_next + 1) % _fx.size()
	chosen.play(position, normal, variant, impact_sound)
	return chosen


## Pone una marca de bala. Sólo se llama para las capas 1 y 8 (`docs/08` §2.10).
## Devuelve `false` si el pool no pudo servirla.
func spawn_decal(position: Vector3, normal: Vector3) -> bool:
	_decal_requests += 1
	if _decals.is_empty():
		return false
	var index := _pick_decal_slot()
	var decal := _decals[index]
	decal.global_position = position
	decal.global_basis = _decal_basis(normal)
	decal.modulate.a = 1.0
	decal.visible = true
	_decal_age[index] = 0.0
	return true


## Impactos que se pidieron al pool de decals desde el arranque. Lo consume
## `weapon_check` para el sub-check de la capa 1.
func get_decal_requests() -> int:
	return _decal_requests


## Decals visibles ahora mismo.
func get_live_decal_count() -> int:
	var live := 0
	for age: float in _decal_age:
		if age >= 0.0:
			live += 1
	return live


## Efectos en marcha ahora mismo.
func get_live_fx_count() -> int:
	var live := 0
	for fx: ImpactFX in _fx:
		if fx.is_playing():
			live += 1
	return live


## Apaga todo y reinicia los contadores. Lo usa el respawn y los checks.
func clear() -> void:
	for fx: ImpactFX in _fx:
		fx.stop()
	for index: int in _decals.size():
		_retire_decal(index)
	_decal_requests = 0


## Variante de [enum ImpactFX.Variant] que le toca a una capa de física.
static func variant_for_layer(layer: int) -> int:
	if (layer & PhysicsLayers.ENEMY_WEAK) != 0:
		return ImpactFX.Variant.WEAK
	if (layer & PhysicsLayers.ENEMY_BODY) != 0:
		return ImpactFX.Variant.METAL
	if (layer & PhysicsLayers.CITY) != 0:
		return ImpactFX.Variant.CONCRETE
	if (layer & PhysicsLayers.DEBRIS) != 0:
		return ImpactFX.Variant.DEBRIS
	return ImpactFX.Variant.GROUND


## `true` si una capa lleva marca de bala: sólo `world` (1) y `city` (8).
static func layer_takes_decal(layer: int) -> bool:
	return (layer & (PhysicsLayers.WORLD | PhysicsLayers.CITY)) != 0


# --- Construcción ----------------------------------------------------------------------------


func _build_fx() -> void:
	var scene := fx_scene
	if scene == null:
		scene = load(FX_SCENE) as PackedScene
	if scene == null:
		push_error("ImpactFXPool: no se pudo cargar %s." % FX_SCENE)
		return
	for index: int in FX_COUNT:
		var instance := scene.instantiate() as ImpactFX
		if instance == null:
			push_error("ImpactFXPool: %s no instancia un ImpactFX." % FX_SCENE)
			return
		instance.name = "ImpactFX%d" % (index + 1)
		add_child(instance)
		_fx.append(instance)


func _build_decals() -> void:
	_decal_texture = _make_decal_texture()
	_decal_age.resize(DECAL_COUNT)
	for index: int in DECAL_COUNT:
		var decal := Decal.new()
		decal.name = "Decal%d" % (index + 1)
		decal.size = Vector3(DECAL_SIZE, DECAL_SIZE, DECAL_SIZE)
		decal.texture_albedo = _decal_texture
		decal.albedo_mix = DECAL_ALBEDO_MIX
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = DECAL_FADE_BEGIN
		decal.cull_mask = 0xFFFFF
		decal.visible = false
		add_child(decal)
		_decals.append(decal)
		_decal_age[index] = -1.0


## Marca de bala procedural: un disco oscuro con borde difuso. Se genera en código
## para no depender de ningún asset externo (sala limpia, `docs/13`).
func _make_decal_texture() -> Texture2D:
	var side := 64
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var center := float(side - 1) * 0.5
	for y: int in side:
		for x: int in side:
			var dx := (float(x) - center) / center
			var dy := (float(y) - center) / center
			var r := sqrt(dx * dx + dy * dy)
			# Núcleo opaco hasta 0.45 y caída suave hasta el borde del cuadro.
			var alpha := clampf(1.0 - smoothstep(0.42, 1.0, r), 0.0, 1.0)
			var shade := lerpf(0.05, 0.28, clampf(r / 0.9, 0.0, 1.0))
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(image)


## Primera ranura libre; si no hay, la más vieja.
func _pick_decal_slot() -> int:
	for offset: int in _decals.size():
		var index := (_decal_next + offset) % _decals.size()
		if _decal_age[index] < 0.0:
			_decal_next = (index + 1) % _decals.size()
			return index
	var oldest := 0
	var best := -1.0
	for index: int in _decals.size():
		if _decal_age[index] > best:
			best = _decal_age[index]
			oldest = index
	_decal_next = (oldest + 1) % _decals.size()
	return oldest


func _retire_decal(index: int) -> void:
	_decal_age[index] = -1.0
	_decals[index].visible = false


## Base de un decal: proyecta a lo largo de `−Y` local, que es el eje de un
## [Decal] en Godot, así que `−Y` tiene que apuntar **hacia** la superficie.
func _decal_basis(normal: Vector3) -> Basis:
	var axis := normal if normal.length_squared() > 0.0001 else Vector3.UP
	axis = axis.normalized()
	var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := helper.cross(axis).normalized()
	var forward := right.cross(axis).normalized()
	return Basis(right, axis, forward)
