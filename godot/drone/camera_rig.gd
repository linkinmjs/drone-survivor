## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Soporte de la cámara FPV dentro del dron (`docs/03` §5 y §8, `docs/13` §6).
##
## Es el **único** nodo que escribe la transformada de la cámara. La `FPVCamera`
## cuelga de acá con transformada identidad y nunca se mueve por su cuenta: todo lo
## que desplace o gire la vista —la inclinación del hangar y la sacudida de trauma—
## pasa por este nodo. Así, quien quiera saber hacia dónde mira el piloto lee una sola
## transformada y no tiene que componer dos.
##
## ## Lo que aplica
##
## - **Inclinación**: `rotation.x = deg_to_rad(QuadSettings.angle)`, con el ángulo
##   positivo levantando el morro de la cámara, que es la convención del hangar
##   (`docs/04` §3.6, rango −20..80°). Se refresca sola en `settings_updated`; el
##   [DroneRig] además la empuja al arrancar (`docs/03` §8).
## - **Sacudida** (WP-28, `docs/13` §6): un modelo de trauma que se suma **encima** de
##   la inclinación. La base es lo que había antes de que empezara la sacudida —la
##   inclinación del hangar, o lo que un check haya escrito a mano— y el temblor es un
##   desplazamiento que se le suma; al extinguirse se reescribe la base exacta, sin
##   error acumulado.
##
## ## El modelo de trauma
##
## `_trauma` vive en `[0, 1]`, se suma con [method add_trauma] (nunca pasa de 1.0) y
## cae [member decay_per_second] por segundo:
## `_trauma = maxf(_trauma - decay_per_second * delta, 0.0)`. Con trauma 1.0 y 1.4/s
## la sacudida se extingue en 0.72 s.
##
## Lo que se **aplica** no es el trauma sino su cuadrado. Es la diferencia entre una
## sacudida chica que se siente sutil y una grande que se siente violenta: con relación
## lineal, el disparo de 0.03 (`docs/08` §2.10) y el pisotón de 0.60 (`docs/07`) se
## diferencian veinte veces; con el cuadrado, cuatrocientas.
##
## El temblor sale de un [FastNoiseLite] (`TYPE_SIMPLEX_SMOOTH`, frecuencia 0.9) y no
## de `randf()` porque tiene que ser **continuo**: un ruido blanco por frame es un
## parpadeo, no una sacudida, y además dependería de la tasa de refresco. Tres muestras
## del mismo ruido en carriles separados —`(t, 0)`, `(t, 37)` y `(t, 74)`— dan las tres
## componentes del desplazamiento, y la misma técnica en tres carriles más
## —`(t, 111)`, `(t, 148)` y `(t, 185)`— da las de la rotación. Son carriles distintos
## a propósito: con los mismos seis números, girar y trasladar quedarían en fase y la
## cámara se movería como una pieza rígida sobre un riel.
##
## La semilla es `RoundManager.derive_seed("camera")` (`docs/11` §4.4), que es un hash
## de [member Global.round_seed]: sin ronda en curso esa semilla vale 0 y el derivado
## sigue siendo determinista, así que dos corridas del mismo check sacuden igual.
##
## ## Por qué avanza en `_process` y no en `_physics_process`
##
## La cámara es **visual**: no participa de ninguna integración y nada de física la
## lee. Avanzarla por frame de render la deja suave a cualquier tasa de refresco sin
## interpolación y —lo que importa más— garantiza que `flight_check` y `flight_bench`
## midan exactamente los mismos números con y sin sacudida.
##
## El `_process` se enciende al empezar una sacudida y se apaga al terminarla: sin
## trauma el nodo no pide frames. Para los pasos exactos, [method tick] es pública: un
## check pone [member auto_tick] en `false` y la llama a mano, como hace [FPVOverlay]
## con su `set_process(false)`.
##
## ## La sacudida llega sola al ojo de pez y al HUD
##
## Las sub-cámaras de las `SubViewport` del ojo de pez copian la transformada **global**
## de la `FPVCamera` en cada frame (`fpv_camera.gd`, `SYNC_PRIORITY`), y el horizonte
## del `FlightHUD` en modo `camera` se dibuja proyectando con esa misma cámara
## (`docs/12` §3): mover este nodo mueve la imagen y el instrumental juntos, sin ningún
## sistema que sincronizar (`docs/13` §6).
class_name CameraRig
extends Node3D

## Desplazamiento máximo de la sacudida, en metros, con trauma 1.0 (`docs/13` §9).
@export var max_translation: float = 0.08

## Rotación máxima de la sacudida, en grados, con trauma 1.0 (`docs/13` §9).
@export var max_rotation_degrees: float = 2.5

## Cuánto trauma se pierde por segundo (`docs/13` §9).
@export var decay_per_second: float = 1.4

## Velocidad con la que se recorre el ruido: multiplica al `delta` antes de muestrear.
@export var noise_speed: float = 22.0

## Frecuencia del [FastNoiseLite] (`docs/13` §9).
const NOISE_FREQUENCY: float = 0.9

## Etiqueta de [method RoundManager.derive_seed] con la que se siembra el ruido.
const NOISE_TAG: String = "camera"

## Carriles del ruido para las tres componentes del desplazamiento (`docs/13` §6).
const TRANSLATION_LANES: Vector3 = Vector3(0.0, 37.0, 74.0)

## Carriles del ruido para las tres componentes de la rotación: la misma técnica en
## carriles propios, para que girar y trasladar no queden en fase.
const ROTATION_LANES: Vector3 = Vector3(111.0, 148.0, 185.0)

## Distancia a la que la atenuación de `camera_trauma` llega a su piso (`docs/13` §6).
const DISTANCE_FALLOFF: float = 80.0

## Piso de la atenuación por distancia: ni el derrumbe más lejano se pierde del todo.
const MIN_ATTENUATION: float = 0.15

## Techo del trauma acumulado. Sumar nunca lo pasa (`docs/13` §10.4, fila 6).
const MAX_TRAUMA: float = 1.0

## Cada cuánto se repliega el reloj del ruido. No introduce ningún salto porque solo
## se repliega al **empezar** una sacudida, con el desplazamiento ya en cero; lo que
## evita es que una partida larga muestree el ruido con enteros de siete cifras, donde
## el flotante de 32 bits de [FastNoiseLite] ya no distingue dos frames seguidos.
const NOISE_WRAP: float = 4096.0

## Inclinación aplicada ahora mismo, en grados. Es lo que se leyó de `QuadSettings`.
var _tilt_degrees: float = 0.0

## Trauma acumulado, de 0.0 a 1.0.
var _trauma: float = 0.0

## Reloj del ruido. Solo avanza mientras hay sacudida.
var _noise_time: float = 0.0

## `true` entre el primer [method add_trauma] y la vuelta exacta a la base.
var _shaking: bool = false

## Posición base, capturada al empezar la sacudida.
var _base_position: Vector3 = Vector3.ZERO

## Rotación base, capturada al empezar la sacudida y corregida por
## [method set_tilt_degrees] mientras dura.
var _base_rotation: Vector3 = Vector3.ZERO

var _noise: FastNoiseLite = null

## Si el nodo avanza la sacudida solo, un frame por vez, desde [method _process].
##
## Lo apaga `shake_check`, que necesita medir en pasos exactos y llama a [method tick]
## a mano. Es una bandera y no un `set_process(false)` porque el nodo **enciende y
## apaga su propio `_process`** según haya sacudida o no: un `set_process(false)` de
## afuera duraba hasta el siguiente [method add_trauma].
var auto_tick: bool = true:
	set(value):
		auto_tick = value
		_refresh_process()


## Las conexiones van en `_enter_tree`/`_exit_tree` y no en `_ready`, que corre **una
## sola vez**: un rig que se reparenta —el dron que cambia de nivel, un check que lo
## saca y lo vuelve a poner— sale del árbol, se desconecta y vuelve a entrar sin
## volver a estar «listo». Con las conexiones en `_ready` volvía mudo: ni sacudida ni
## inclinación del hangar, y sin ningún síntoma hasta que el jugador nota que la
## cámara dejó de moverse.
func _enter_tree() -> void:
	_connect_signals()


func _ready() -> void:
	_build_noise()
	set_tilt_degrees(QuadSettings.angle)
	_base_position = position
	# Redundante con [method _enter_tree] en el caso normal; hace falta para el nodo
	# que alguien construyó con `CameraRig.new()` y agregó después.
	_connect_signals()
	_refresh_process()


func _exit_tree() -> void:
	_disconnect_signals()


## Engancha las dos señales de las que vive el nodo, sin duplicar.
func _connect_signals() -> void:
	if not Events.camera_trauma.is_connected(_on_camera_trauma):
		var _discard := Events.camera_trauma.connect(_on_camera_trauma)
	if not QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		var _discard := QuadSettings.settings_updated.connect(_on_quad_settings_updated)


## La otra mitad exacta de [method _connect_signals].
func _disconnect_signals() -> void:
	if Events.camera_trauma.is_connected(_on_camera_trauma):
		Events.camera_trauma.disconnect(_on_camera_trauma)
	if QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		QuadSettings.settings_updated.disconnect(_on_quad_settings_updated)


## `_process` corre **solo mientras hay sacudida**. Sin trauma, [method tick] sale por
## la primera línea, así que lo único que quedaba era el coste de la llamada por frame
## de cada dron de la escena; con esto el nodo no aparece ni en el perfilador.
func _refresh_process() -> void:
	set_process(auto_tick and _shaking)


func _process(delta: float) -> void:
	PerfProbe.begin(&"camera_rig")
	tick(delta)
	PerfProbe.end(&"camera_rig")


# --- Inclinación del hangar (`docs/04` §3.6) ---------------------------------------------------

## Inclina la cámara [param angle] grados sobre el eje X del dron. Positivo levanta
## la vista, que es lo que hace un cuadro de carrera para volar rápido sin cabecear.
##
## Sigue funcionando **durante** la sacudida: lo que mueve es la base, y el temblor se
## recompone encima en el acto.
func set_tilt_degrees(angle: float) -> void:
	_tilt_degrees = clampf(angle, QuadSettings.ANGLE_RANGE.x, QuadSettings.ANGLE_RANGE.y)
	_base_rotation = Vector3(deg_to_rad(_tilt_degrees), 0.0, 0.0)
	if _shaking:
		_apply_shake()
	else:
		rotation = _base_rotation


## La inclinación aplicada, en grados.
func get_tilt_degrees() -> float:
	return _tilt_degrees


# --- Trauma (`docs/13` §6) ---------------------------------------------------------------------

## Suma [param amount] de trauma, con techo [constant MAX_TRAUMA].
##
## Es la firma fija de `docs/03` §9. Ignora los valores no finitos y los no positivos:
## un emisor con un perfil sin configurar no debe poder apagar una sacudida en curso.
func add_trauma(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	if not _shaking:
		_begin_shake()
	_trauma = minf(_trauma + amount, MAX_TRAUMA)


## Trauma acumulado, de 0.0 a 1.0.
func get_trauma() -> float:
	return _trauma


## `true` mientras la cámara esté desplazada de su base.
func is_shaking() -> bool:
	return _shaking


## Apaga la sacudida en el acto y devuelve la cámara a su base, sin esperar al
## decaimiento.
##
## Es para quien necesite **ser dueño** de la transformada durante un rato:
## `hud_projection_check` posa la cámara en actitudes fijas y `weapon_check` la mete en
## el centro del casco, y un derrumbe a destiempo les movería la regla. Fuera de los
## checks no la llama nadie: en el juego la sacudida siempre termina sola.
func clear_trauma() -> void:
	if not _shaking:
		return
	_end_shake()


## Avanza la sacudida [param delta] segundos.
##
## La llama [method _process] con el `delta` del motor; un check la llama a mano tras
## poner [member auto_tick] en `false`, para medir en pasos exactos. Sin sacudida en
## curso no escribe la transformada: así un check que quiera posar la cámara a mano
## —`weapon_check`, `hud_projection_check`— sigue siendo dueño de ella.
func tick(delta: float) -> void:
	if not _shaking:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_noise_time += delta * noise_speed
	_trauma = maxf(_trauma - decay_per_second * delta, 0.0)
	if _trauma <= 0.0:
		_end_shake()
		return
	_apply_shake()


## Desplazamiento que la sacudida le está sumando a la base, en metros.
func translation_offset() -> Vector3:
	if not _shaking:
		return Vector3.ZERO
	return _lanes(TRANSLATION_LANES).limit_length(1.0) * max_translation * _intensity()


## Rotación que la sacudida le está sumando a la base, en radianes por eje.
func rotation_offset() -> Vector3:
	if not _shaking:
		return Vector3.ZERO
	return _lanes(ROTATION_LANES).limit_length(1.0) \
			* deg_to_rad(max_rotation_degrees) * _intensity()


## Posición base: la que la cámara recupera al extinguirse el trauma.
func base_position() -> Vector3:
	return _base_position if _shaking else position


## Rotación base, en radianes. Es la inclinación del hangar salvo que alguien haya
## escrito la rotación a mano antes de la sacudida.
func base_rotation() -> Vector3:
	return _base_rotation


## Semilla del ruido. La miran los checks de determinismo.
func noise_seed() -> int:
	return _noise.seed if _noise != null else 0


## Resiembra el ruido y reinicia su reloj. No es para el juego —la semilla sale de la
## ronda—: es para que un check pueda demostrar que la semilla **manda**.
func set_noise_seed(value: int) -> void:
	if _noise == null:
		_build_noise()
	_noise.seed = value
	_noise_time = 0.0


# --- Interno -----------------------------------------------------------------------------------

func _build_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = NOISE_FREQUENCY
	_noise.seed = RoundManager.derive_seed(NOISE_TAG)


## El factor que se aplica al desplazamiento: `trauma²` (`docs/13` §6).
func _intensity() -> float:
	return _trauma * _trauma


## Las tres muestras del ruido en los carriles [param lanes], cada una en `[-1, 1]`.
func _lanes(lanes: Vector3) -> Vector3:
	if _noise == null:
		return Vector3.ZERO
	return Vector3(
			_noise.get_noise_2d(_noise_time, lanes.x),
			_noise.get_noise_2d(_noise_time, lanes.y),
			_noise.get_noise_2d(_noise_time, lanes.z))


## Captura la base y arranca la sacudida.
##
## La base se toma del nodo y no de la inclinación calculada porque el dueño de la
## transformada puede no ser el hangar: `weapon_check` mete la cámara en el centro del
## casco y `hud_projection_check` la posa en actitudes fijas. Volver «a la base» tiene
## que significar volver a **lo que había**, no a lo que el hangar diría.
func _begin_shake() -> void:
	if _shaking:
		return
	_base_position = position
	_base_rotation = rotation
	_noise_time = fmod(_noise_time, NOISE_WRAP)
	_shaking = true
	_refresh_process()


## Escribe la base exacta y apaga la sacudida. El error contra la base es cero, no
## «pequeño»: se reescribe el valor guardado y no se resta el último desplazamiento.
func _end_shake() -> void:
	_trauma = 0.0
	_shaking = false
	_refresh_process()
	position = _base_position
	rotation = _base_rotation


func _apply_shake() -> void:
	var intensity := _intensity()
	position = _base_position \
			+ _lanes(TRANSLATION_LANES).limit_length(1.0) * max_translation * intensity
	rotation = _base_rotation \
			+ _lanes(ROTATION_LANES).limit_length(1.0) \
			* deg_to_rad(max_rotation_degrees) * intensity


## Atenuación por distancia de `camera_trauma` (`docs/13` §6). Una posición no finita
## —`Vector3.INF`, el acuse de objetivo completado de `docs/11` §5.2— significa «esto
## no pasa en ningún lado»: entra entero.
func _attenuation(at_position: Vector3) -> float:
	if not at_position.is_finite():
		return 1.0
	var distance := global_position.distance_to(at_position)
	return clampf(1.0 - distance / DISTANCE_FALLOFF, MIN_ATTENUATION, 1.0)


func _on_camera_trauma(amount: float, at_position: Vector3) -> void:
	add_trauma(amount * _attenuation(at_position))


func _on_quad_settings_updated() -> void:
	set_tilt_degrees(QuadSettings.angle)
