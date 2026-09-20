## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Los trazadores del arma, en **una sola llamada de dibujo** (`docs/08` §2.9).
##
## Es un [MultiMeshInstance3D] con 96 instancias de un `QuadMesh` unitario y
## `use_custom_data = true`. El nodo se queda con la transformada identidad y
## todas las instancias se escriben en **coordenadas de mundo**: es legal y es lo
## correcto, porque los proyectiles no son hijos de nadie.
##
## El desvanecido no se calcula acá. Cada tick se escribe
## `INSTANCE_CUSTOM = Color(life, length_scale, 0, 0)` y el `tracer.gdshader` hace
## `ALPHA *= INSTANCE_CUSTOM.r`. Un `Tween` o un `lerp` por trazador en GDScript
## costaría 96 llamadas por frame para algo que la GPU ya tiene en el vértice.
##
## **Compactación**: las ranuras vivas se mueven al principio del búfer en cada
## escritura y `visible_instance_count` queda en el número exacto de vivos. Sin
## esto, la instancia de un trazador liberado se queda dibujada con su última
## transformada —un palo fantasma clavado en el aire— porque el `MultiMesh` no
## tiene forma de «apagar» una instancia suelta.
##
## Uso, por tick y por proyectil con trazador:
## [codeblock]
## var slot := tracers.acquire()
## tracers.write(slot, projectile.position, projectile.direction(), projectile.life_ratio())
## tracers.release(slot)
## tracers.commit()
## [/codeblock]
class_name TracerRenderer extends MultiMeshInstance3D

## Instancias preasignadas (`docs/08` §4): 256 / 3 con margen.
const INSTANCE_COUNT: int = 96

## Largo del segmento de trazador, en metros.
const SEGMENT_LENGTH: float = 6.0

## Ancho del segmento de trazador, en metros.
const SEGMENT_WIDTH: float = 0.08

## Ruta del shader del trazador.
const SHADER_PATH: String = "res://drone/weapons/tracer.gdshader"

## Valor que devuelve [method acquire] cuando no queda ninguna ranura libre.
const NO_SLOT: int = -1

## Transformada con la que se aparcan las ranuras sobrantes: los tres ejes en cero,
## o sea escala cero, para que ni siquiera lleguen al rasterizador si algo se
## saltara la compactación. Se escribe con los cuatro vectores y no con
## `Basis.IDENTITY.scaled(...)` porque una llamada a método no es una expresión
## constante en GDScript.
const PARKED: Transform3D = Transform3D(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

var _free_slots: PackedInt32Array = PackedInt32Array()
var _slot_transform: Array[Transform3D] = []
var _slot_custom: PackedColorArray = PackedColorArray()
var _slot_live: PackedByteArray = PackedByteArray()
var _live_count: int = 0


func _ready() -> void:
	_build_multimesh()


## Construye el [MultiMesh] y el material. Se llama una sola vez: en caliente no
## se asigna nada.
func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _build_material()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = INSTANCE_COUNT
	mm.visible_instance_count = 0
	multimesh = mm

	transform = Transform3D.IDENTITY
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Los trazadores se escriben en mundo y viajan 600 m: sin una AABB propia el
	# culling los borraría en cuanto el nodo (que está en el origen) saliera de
	# cuadro.
	custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))

	_slot_transform.resize(INSTANCE_COUNT)
	_slot_custom.resize(INSTANCE_COUNT)
	_slot_live.resize(INSTANCE_COUNT)
	_free_slots.resize(INSTANCE_COUNT)
	for index: int in INSTANCE_COUNT:
		_slot_transform[index] = PARKED
		_slot_custom[index] = Color(0.0, 0.0, 0.0, 0.0)
		_slot_live[index] = 0
		# Pila: se sirve por el final, así que el orden inverso entrega la 0 primero.
		_free_slots[index] = INSTANCE_COUNT - 1 - index
		mm.set_instance_transform(index, PARKED)
		mm.set_instance_custom_data(index, Color(0.0, 0.0, 0.0, 0.0))
	_live_count = 0


func _build_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_error("TracerRenderer: no se pudo cargar %s." % SHADER_PATH)
		return material
	material.shader = shader
	return material


## Toma una ranura libre, o [constant NO_SLOT] si las 96 están ocupadas. O(1).
func acquire() -> int:
	var free_count := _free_slots.size()
	if free_count <= 0:
		return NO_SLOT
	var slot := _free_slots[free_count - 1]
	_free_slots.resize(free_count - 1)
	_slot_live[slot] = 1
	_live_count += 1
	return slot


## Escribe la transformada y la vida de [param slot]. [param direction] tiene que
## venir normalizada; [param life_ratio] va de 1.0 (recién disparado) a 0.0.
func write(slot: int, origin: Vector3, direction: Vector3, life_ratio: float) -> void:
	if slot < 0 or slot >= INSTANCE_COUNT or _slot_live[slot] == 0:
		return
	_slot_transform[slot] = _segment_transform(origin, direction)
	_slot_custom[slot] = Color(clampf(life_ratio, 0.0, 1.0), SEGMENT_LENGTH, 0.0, 0.0)


## Devuelve [param slot] a la lista libre. O(1).
func release(slot: int) -> void:
	if slot < 0 or slot >= INSTANCE_COUNT or _slot_live[slot] == 0:
		return
	_slot_live[slot] = 0
	_slot_transform[slot] = PARKED
	_slot_custom[slot] = Color(0.0, 0.0, 0.0, 0.0)
	_free_slots.append(slot)
	_live_count = maxi(_live_count - 1, 0)


## Vuelca las ranuras vivas **compactadas** al principio del búfer y ajusta
## `visible_instance_count`. Se llama una vez por tick, después de escribir todos
## los trazadores.
func commit() -> void:
	if multimesh == null:
		return
	var written := 0
	for slot: int in INSTANCE_COUNT:
		if _slot_live[slot] == 0:
			continue
		multimesh.set_instance_transform(written, _slot_transform[slot])
		multimesh.set_instance_custom_data(written, _slot_custom[slot])
		written += 1
	multimesh.visible_instance_count = written


## Deja el búfer vacío y todas las ranuras libres.
func clear() -> void:
	for slot: int in INSTANCE_COUNT:
		_slot_live[slot] = 0
		_slot_transform[slot] = PARKED
		_slot_custom[slot] = Color(0.0, 0.0, 0.0, 0.0)
	_free_slots.resize(INSTANCE_COUNT)
	for index: int in INSTANCE_COUNT:
		_free_slots[index] = INSTANCE_COUNT - 1 - index
	_live_count = 0
	if multimesh != null:
		multimesh.visible_instance_count = 0


## Trazadores vivos ahora mismo.
func get_live_count() -> int:
	return _live_count


## Ranuras libres.
func get_free_count() -> int:
	return _free_slots.size()


## Vida escrita en `INSTANCE_CUSTOM.r` de [param slot]; `−1.0` si la ranura no
## está viva. Lo consume `weapon_check` para comprobar que el desvanecido decrece.
func get_slot_life(slot: int) -> float:
	if slot < 0 or slot >= INSTANCE_COUNT or _slot_live[slot] == 0:
		return -1.0
	return _slot_custom[slot].r


## Transformada de un segmento: origen en la posición del proyectil, `+Y` local a
## lo largo del vuelo y escala `(ancho, largo, 1)`.
func _segment_transform(origin: Vector3, direction: Vector3) -> Transform3D:
	var forward := direction
	if forward.length_squared() <= 0.0:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	# Base arbitraria perpendicular: el shader rehace los ejes X y Z mirando a la
	# cámara, así que acá sólo importa que la base sea ortonormal y que +Y sea el
	# vuelo.
	var helper := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := helper.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	# Las columnas de la base **son** los ejes locales, así que escalarlas una a
	# una es escalar en espacio local. `Basis.scaled()` no sirve acá: premultiplica,
	# o sea escala en ejes de mundo, y el segmento saldría torcido.
	var basis := Basis(right * SEGMENT_WIDTH, forward * SEGMENT_LENGTH, up)
	return Transform3D(basis, origin)
