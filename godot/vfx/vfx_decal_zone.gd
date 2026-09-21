## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Zona de peligro proyectada en el suelo (`docs/13` §4 y §11 #12, `docs/07` §5.4).
##
## Es la telegrafía del pisotón: un [Decal] **rojo** de 18 m de diámetro que
## parpadea a 4 Hz, sigue al punto que le pasa `ActionStomp` —o sea a la posición
## creída del dron— y se **congela** los últimos 0.25 s. Ese congelado es lo que
## hace esquivable el ataque: el jugador ve dónde va a caer el pie y le queda un
## cuarto de segundo para salir. Cuando el pie baja, la zona se apaga y queda una
## marca de cráter durante 4 s.
##
## [b]Cero emisores y pool dedicado[/b] (`docs/13` §11 #12): si el presupuesto de
## partículas pudiera descartar este aviso, el ataque más dañino del jefe se
## quedaría sin señal. No hay ni una partícula acá.
##
## [b]El aviso no miente[/b]: el radio se lo fija la acción desde `shape_radius()`,
## que es el de la [CylinderShape3D] real de la consulta (`docs/06` §11.2).
class_name VFXDecalZone extends VFXEffect

## Parpadeos por segundo del aviso (`docs/07` §5.4).
const BLINK_HZ: float = 4.0

## Opacidad mínima del parpadeo. No baja a 0: un aviso que desaparece medio
## fotograma sí o sí se pierde en el ruido del vídeo FPV.
const BLINK_FLOOR: float = 0.45

## Segundos que dura la marca de cráter, después del golpe.
const CRATER_SECONDS: float = 4.0

## Altura del proyector sobre el punto de suelo, en metros.
##
## **0 y no 3.** La caja de un [Decal] está centrada en su propio origen, así que
## con el nodo 3 m por encima del suelo y [constant PROJECTOR_DEPTH] = 6 la calle
## caía justo en el **borde inferior** de la caja, que es donde `lower_fade` la
## desvanece casi del todo: el aviso se leía como una mancha tenue y el cráter no
## se veía nunca, por más que se le subiera el albedo (fotogramas 208 de tres
## capturas seguidas del showcase). Con el nodo en el punto de suelo, la calle
## queda en el **centro** de la caja y los dos desvanecidos hacen lo que deben,
## que es recortar arriba y abajo.
##
## Lo que evita que la caja pinte la torre de al lado o las patas del jefe no es
## la altura sino `normal_fade`, que borra el decal en cualquier superficie que no
## sea horizontal, más los 6 m de profundidad —±3 m sobre la calle—.
const PROJECTOR_HEIGHT: float = 0.0

## Profundidad de proyección del decal, en metros.
const PROJECTOR_DEPTH: float = 6.0

@onready var _zone: Decal = get_node_or_null(^"Zone") as Decal
@onready var _crater: Decal = get_node_or_null(^"Crater") as Decal

var _radius: float = 9.0
var _ground: Vector3 = Vector3.ZERO
var _frozen: bool = false
var _struck: bool = false
var _blink: float = 0.0
var _crater_left: float = -1.0


func _ready() -> void:
	super()
	if _crater != null:
		_crater.visible = false


func _process(delta: float) -> void:
	super(delta)
	if _zone != null and _zone.visible:
		_blink += delta
		# Onda cuadrada suavizada: sube rápido y baja rápido, pero sin el clac de
		# una cuadrada pura, que a 4 Hz da un parpadeo sucio en pantalla.
		var wave := 0.5 + 0.5 * sin(_blink * BLINK_HZ * TAU)
		_zone.modulate.a = lerpf(BLINK_FLOOR, 1.0, wave * wave)
	if _crater_left < 0.0:
		return
	_crater_left -= delta
	if _crater == null:
		return
	if _crater_left <= 0.0:
		_crater.visible = false
		_crater_left = -1.0
		return
	_crater.modulate.a = clampf(_crater_left / (CRATER_SECONDS * 0.4), 0.0, 1.0)


## Punto de suelo que marca la zona. Mientras no esté congelada, la acción lo
## reescribe en cada tick con la posición creída del dron.
func set_ground_point(point: Vector3) -> void:
	if _frozen:
		return
	_ground = point
	global_position = Vector3(point.x, point.y + PROJECTOR_HEIGHT, point.z)


## Radio real del ataque, en metros. Un decal más grande que el cilindro sería
## mentirle al jugador (`docs/06` §11.2).
func set_radius(radius: float) -> void:
	_radius = maxf(radius, 0.5)
	if _zone != null:
		_zone.size = Vector3(_radius * 2.0, PROJECTOR_DEPTH, _radius * 2.0)


## Congela el punto: de acá en más [method set_ground_point] no mueve nada.
func freeze() -> void:
	_frozen = true


## `true` si la zona ya no se mueve.
func is_frozen() -> bool:
	return _frozen


## Punto donde quedó marcada la zona.
func ground_point() -> Vector3:
	return _ground


## El pie bajó: se apaga el aviso y queda la marca de cráter.
func strike() -> void:
	# El aviso terminó: de acá en más lo único que mantiene viva a la instancia es
	# la marca de cráter. Sin esta bandera, `life_seconds = 0` dejaba `_playing`
	# en `true` para siempre y el pool no recuperaba la ranura hasta la red de
	# `MAX_HOLD_SECONDS` — lo encontró la fila 12 de `vfx_check`.
	_struck = true
	if _zone != null:
		_zone.visible = false
	if _crater == null:
		return
	_crater.size = Vector3(_radius * 1.6, PROJECTOR_DEPTH, _radius * 1.6)
	_crater.modulate.a = 1.0
	_crater.visible = true
	_crater_left = CRATER_SECONDS
	set_process(true)


func _on_play() -> void:
	_frozen = false
	_struck = false
	_blink = 0.0
	_crater_left = -1.0
	set_radius(_radius)
	if _zone != null:
		_zone.modulate.a = 1.0
		_zone.visible = true
	if _crater != null:
		_crater.visible = false


func _on_stop() -> void:
	_frozen = false
	_struck = false
	_crater_left = -1.0
	if _crater != null:
		_crater.visible = false


## La zona sigue viva mientras parpadee **o** mientras quede cráter: el pool no
## puede reciclar la instancia con la marca todavía en la calle. Después del
## golpe manda sólo el cráter.
func is_playing() -> bool:
	if _struck:
		return _crater_left >= 0.0
	return super() or _crater_left >= 0.0
