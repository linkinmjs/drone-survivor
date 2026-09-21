## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Telegrafía de ataque (`docs/06` §11.2 y §12). Reemplaza al placeholder de WP-16.
##
## Hay [b]uno solo por enemigo[/b]: nunca hay dos avisos simultáneos. Enciende
## los tres canales que `docs/06` §11.2 exige —de los que todo ataque dañino
## necesita al menos dos, y los letales los tres— y los apaga en
## [constant FADE_SECONDS] al terminar:
##
## 1. [b]Luz emisiva[/b]: un [OmniLight3D] propio colocado en la cabeza, que va
##    del color de reposo del [TelegraphProfile] al color del ataque mientras
##    sube la energía, más el tinte del emisivo de la carcasa de la cabeza (se
##    guarda el color original y se restaura al apagar).
## 2. [b]Audio[/b]: un [AudioStreamPlayer3D] con el sonido de carga que declara
##    `TelegraphProfile.audio_event` —los sintetiza
##    `tools/generate_enemy_sounds.gd`—, con `unit_size` grande para que se oiga
##    a 80 m, sobre el bus `Enemies`. Sin perfil cae en el barrido genérico
##    `assets/audio/enemies/charge.wav`.
## 3. [b]Señal espacial[/b], según `TelegraphProfile.spatial_kind` (WP-19):
##    [constant TelegraphProfile.SpatialKind.DECAL_ZONE] es el anillo de suelo
##    que crece hasta el radio real del ataque; `GUIDE_LINE` es la línea fina
##    cabeza → objetivo del láser; `COLUMN` es la columna vertical del asedio;
##    `PARABOLA` es el arco del salto; `POSTURE` no dibuja nada —la pone la
##    acción— pero cuenta como canal.
##
## [b]WP-26[/b]: la señal espacial la dibuja ahora el [VFXPool] —el decal rojo de
## 18 m del pisotón, el anillo cian del EMP, la línea guía, la columna ámbar del
## asedio y la parábola punteada del salto—, que las sirve desde pools dedicados
## con [b]cero emisores de partículas[/b] (`docs/13` §11 #12): el presupuesto no
## puede descartar un aviso. Las mallas de WP-19 se conservan como [b]respaldo[/b]
## y se encienden solas cuando no hay pool en el árbol, que es lo que pasa en los
## bancos sintéticos de `ai_check` y `enemy_parts_check`.
##
## El `DECAL_ZONE` se reparte en dos efectos según el ataque: el pisotón pide
## `stomp_decal` (rojo, parpadeo a 4 Hz, se congela) y todo lo demás —el EMP— pide
## `emp_ring` (cian, crece con un `Tween`). Los distingue
## [member TelegraphProfile.decal_grow_from]: el anillo que nace en 0 es una onda
## que se expande, y el que nace en 0.25 es una zona que hay que abandonar.
##
## Al empezar publica `Events.enemy_attack_telegraphed(enemy, attack_id,
## duration)`, que es lo que consume el aviso del `CombatHUD` (`docs/12`) y lo
## que mide `ai_check` para comprobar que el aviso precede al daño.
##
## [b]El perfil es opcional[/b]: sin él el aviso se comporta exactamente como en
## WP-18 (anillo de suelo, `charge.wav`, color pasado por parámetro). Eso deja
## intactas las acciones de P3 que todavía no declaren [TelegraphProfile].
class_name Telegraph extends Node3D

## Segundos que tardan los tres canales en apagarse (`docs/06` §11.2).
const FADE_SECONDS: float = 0.15

## Radio del anillo de suelo cuando el ataque no declara ninguno, en metros.
const DEFAULT_RADIUS: float = 9.0

## Altura del anillo sobre el suelo, en metros. Suficiente para no pelearse con
## el z-fighting de la calle sin despegarse de ella.
const RING_LIFT: float = 0.25

## Grosor del anillo, como fracción de su radio.
const RING_THICKNESS: float = 0.14

## Energía máxima de la luz de carga.
const LIGHT_ENERGY: float = 24.0

## Intensidad máxima de la luz de carga, en lúmenes.
##
## El proyecto corre con `use_physical_light_units` (`docs/02` §2), y en ese modo
## las luces omni se miden en lúmenes: fijar sólo `light_energy` no se vería.
##
## **90 000 → 30 000 (WP-26, #7).** Medido en los fotogramas de la batalla con el
## bot: a 30 m del pisotón la luz de carga teñía de rojo media imagen y **ahogaba
## el decal**, que es el canal que lleva el «dónde va a caer el pie». El canal 1
## de `docs/06` §11.2 sigue cumpliéndose —el emisivo de la cabeza vira igual y
## pasa el umbral de glow—, pero deja de competir con el canal 3. El cambio es
## para **todos** los avisos: ver la nota de [constant LIGHT_RANGE].
const LIGHT_LUMENS: float = 30000.0

## Alcance de la luz de carga, en metros.
##
## **60 → 40 (WP-26, #7).** Acompaña a [constant LIGHT_LUMENS]: con 60 m la luz
## llegaba a edificios que no tenían nada que ver con el ataque y los pintaba del
## color del aviso.
##
## Se baja para todos los ataques y no sólo para `stomp` y `pounce` porque
## [TelegraphProfile] no tiene con qué distinguirlos: lo único que expone es
## [member TelegraphProfile.light_energy_to], que es la **forma** de la rampa de 0
## a 1 y no un brillo absoluto, y los ocho `.tres` los hornea
## `tools/build_arachnodroid_profile.gd` desde una tabla y no se editan a mano
## (WP-19). Bajar sólo dos ataques obligaría a tocar el generador y a re-hornear
## los ocho perfiles de aviso más los de ataque, que es mucha remoción en archivos
## de WP-19 para un ajuste de luz. Si más adelante hace falta el control por
## ataque, lo natural es un campo nuevo `light_lumens` en [TelegraphProfile].
const LIGHT_RANGE: float = 40.0

## Distancia de referencia del audio de carga, en metros (`docs/06` §11.2: se
## tiene que oír a 80 m).
const AUDIO_UNIT_SIZE: float = 60.0

## Ruta del sonido de carga por defecto.
const CHARGE_STREAM: String = "res://assets/audio/enemies/charge.wav"

## Bus de audio de los enemigos (`docs/07` §10).
const AUDIO_BUS: StringName = &"Enemies"

## Color de reposo del que arranca la carga: el cian de la paleta del
## Arachnodroid (`docs/07` §2).
const REST_COLOR: Color = Color(0.216, 0.667, 0.973)

## Altura de la columna del asedio, en metros. Cubre de sobra la torre más alta
## del pack de ciudad (`docs/10` §4.2).
const COLUMN_HEIGHT: float = 120.0

## Radio de la columna del asedio, en metros (`docs/07` §5.7: el haz tiene r 2.5).
const COLUMN_RADIUS: float = 2.5

## Segmentos con los que se dibuja la parábola guía del salto.
const PARABOLA_SEGMENTS: int = 18

## Ids de [VFXPool] de cada tipo de señal espacial (`docs/13` §4).
const VFX_STOMP: StringName = &"stomp_decal"
const VFX_RING: StringName = &"emp_ring"
const VFX_GUIDE: StringName = &"guide_line"
const VFX_COLUMN: StringName = &"siege_column"
const VFX_PARABOLA: StringName = &"parabola"

## Rojo de peligro de `UIPalette.DANGER` (`docs/13` §2.2). Es el del decal del
## pisotón y el de la parábola del salto: los dos anuncian daño al dron.
const DANGER_COLOR: Color = Color(1.0, 0.302, 0.302)

## Enemigo dueño del aviso. Si queda vacío se toma el padre.
@export var enemy: Node3D = null

## Si el aviso enciende la luz y la señal espacial. Un check headless puede
## apagarlo.
@export var visuals_enabled: bool = true

var _light: OmniLight3D = null
var _ring: MeshInstance3D = null
var _ring_mesh: TorusMesh = null
var _ring_material: StandardMaterial3D = null
var _guide: MeshInstance3D = null
var _guide_mesh: ImmediateMesh = null
var _guide_material: StandardMaterial3D = null
var _column: MeshInstance3D = null
var _column_mesh: CylinderMesh = null
var _column_material: StandardMaterial3D = null
var _audio: AudioStreamPlayer3D = null
var _head: Node3D = null
var _tinted: Array[Dictionary] = []
var _streams: Dictionary[StringName, AudioStream] = {}

var _pool: VFXPool = null
var _vfx: Node3D = null
var _vfx_id: StringName = &""

var _profile: TelegraphProfile = null
var _attack_id: StringName = &""
var _duration: float = 0.0
var _elapsed: float = 0.0
var _fade_left: float = 0.0
var _radius: float = DEFAULT_RADIUS
var _color: Color = REST_COLOR
var _rest_color: Color = REST_COLOR
var _ground_point: Vector3 = Vector3.ZERO
var _has_ground_point: bool = false
var _guide_target: Vector3 = Vector3.ZERO
var _has_guide_target: bool = false
var _running: bool = false
var _channels: int = 0
var _kind: int = TelegraphProfile.SpatialKind.DECAL_ZONE


func _ready() -> void:
	if enemy == null:
		enemy = get_parent() as Node3D
	_build_channels()


## Apaga el aviso con un desvanecido de [constant FADE_SECONDS]. Acumulador,
## nunca un [Timer].
func _physics_process(delta: float) -> void:
	if _running or _fade_left <= 0.0 or delta <= 0.0:
		return
	PerfProbe.begin(&"telegraph")
	_fade_left = maxf(0.0, _fade_left - delta)
	var ratio := _fade_left / FADE_SECONDS
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * ratio
		_light.light_intensity_lumens = LIGHT_LUMENS * ratio
	if _ring != null:
		_ring_material.albedo_color.a = ratio * 0.65
	if _guide != null:
		_guide_material.albedo_color.a = ratio * 0.85
	if _column != null:
		_column_material.albedo_color.a = ratio * 0.45
	if _fade_left <= 0.0:
		_shutdown()
	PerfProbe.end(&"telegraph")


# --------------------------------------------------------------------------
# Interfaz pública
# --------------------------------------------------------------------------

## Fija el [TelegraphProfile] del ataque que está por telegrafiarse. Lo llama el
## estado `TELEGRAPH` **antes** de [method begin]; `null` devuelve el aviso a su
## comportamiento por defecto (anillo de suelo y `charge.wav`).
func set_profile(cfg: TelegraphProfile) -> void:
	_profile = cfg
	if cfg == null:
		_kind = TelegraphProfile.SpatialKind.DECAL_ZONE
		_rest_color = REST_COLOR
		_radius = DEFAULT_RADIUS
		return
	_kind = cfg.spatial_kind
	_rest_color = cfg.light_color_from
	if cfg.decal_radius > 0.0:
		_radius = cfg.decal_radius


## Perfil vigente, o `null`.
func profile() -> TelegraphProfile:
	return _profile


## Arranca el aviso de [param attack_id] por [param seconds], con la carga
## virando hacia [param color].
##
## [param spatial] es el nodo sobre el que se proyecta la señal espacial; sin él
## se usa el punto fijado con [method set_ground_point] o, en su defecto, el
## propio enemigo.
func begin(attack_id: StringName, seconds: float, color: Color = REST_COLOR,
		spatial: Node3D = null) -> void:
	_attack_id = attack_id
	_duration = maxf(seconds, 0.0001)
	_elapsed = 0.0
	_fade_left = 0.0
	_color = _profile.light_color_to if _profile != null else color
	_running = true
	_ensure_head()
	if spatial != null:
		set_ground_point(spatial.global_position)
	_channels = 0

	if visuals_enabled and _light != null:
		_light.visible = true
		_light.global_position = _head.global_position if _head != null else global_position
		_light.light_color = _rest_color
		_light.light_energy = LIGHT_ENERGY * _energy_ramp(0.0)
		_light.light_intensity_lumens = LIGHT_LUMENS * _energy_ramp(0.0)
		_channels += 1
		_tint_head(_rest_color)
	_audio.stream = _stream_for(_audio_event())
	if _audio != null and _audio.stream != null:
		_audio.play()
		_channels += 1
	if _begin_spatial():
		_channels += 1

	# El aviso por el bus va **último**, con los canales ya encendidos: es lo que
	# consume el `CombatHUD` (`docs/12`) y lo que miden `ai_check` y
	# `arachnodroid_check` para comprobar que la telegrafía precede al daño.
	var host := enemy if enemy != null else self
	Events.enemy_attack_telegraphed.emit(host, attack_id, seconds)


## Avanza la carga. Lo llama el estado `TELEGRAPH` en cada tick de física.
func tick(delta: float) -> void:
	if not _running or delta <= 0.0:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if _light != null and _light.visible:
		if _head != null:
			_light.global_position = _head.global_position
		_light.light_color = _rest_color.lerp(_color, t)
		var ramp := _energy_ramp(t)
		_light.light_energy = LIGHT_ENERGY * ramp
		_light.light_intensity_lumens = LIGHT_LUMENS * ramp
		_tint_head(_rest_color.lerp(_color, t))
	_tick_spatial(t)


## Termina el aviso: los tres canales se apagan en [constant FADE_SECONDS].
func end() -> void:
	if not _running:
		return
	_running = false
	_fade_left = FADE_SECONDS
	if _audio != null:
		_audio.stop()


## Alias de [method end] con el nombre del placeholder de WP-16.
func cancel() -> void:
	end()


## Fija el punto de suelo sobre el que se proyecta la señal espacial.
func set_ground_point(point: Vector3) -> void:
	_ground_point = point
	_has_ground_point = true


## Fija el punto al que apuntan la línea guía, la columna o la parábola.
func set_guide_target(point: Vector3) -> void:
	_guide_target = point
	_has_guide_target = true
	if _kind == TelegraphProfile.SpatialKind.COLUMN \
			or _kind == TelegraphProfile.SpatialKind.PARABOLA:
		set_ground_point(point)


## Fija el radio del anillo de suelo, en metros.
func set_radius(radius: float) -> void:
	_radius = maxf(radius, 0.5)


## `true` mientras el aviso está encendido.
func is_active() -> bool:
	return _running


## Progreso del aviso, de 0 a 1.
func progress() -> float:
	return clampf(_elapsed / _duration, 0.0, 1.0) if _duration > 0.0 else 0.0


## Id del ataque anunciado.
func attack_id() -> StringName:
	return _attack_id


## Duración anunciada, en segundos.
func duration() -> float:
	return _duration


## Canales encendidos en el último [method begin]: luz, audio y señal espacial.
## `docs/06` §11.2 exige al menos dos, y tres en los ataques letales.
func active_channels() -> int:
	return _channels


## Tipo de señal espacial del aviso en curso.
func spatial_kind() -> int:
	return _kind


## `true` si el canal de audio tiene sonido cargado.
func has_audio() -> bool:
	return _audio != null and _audio.stream != null


# --------------------------------------------------------------------------
# Señal espacial (`docs/06` §11.2 canal 3)
# --------------------------------------------------------------------------

## Enciende la señal espacial que pide el perfil. Devuelve `true` si el canal
## cuenta: `POSTURE` no dibuja nada pero es un canal legítimo, porque la acción
## se encarga de la pose (`docs/07` §5.5 y §5.9).
func _begin_spatial() -> bool:
	if _kind == TelegraphProfile.SpatialKind.NONE:
		return false
	if _kind == TelegraphProfile.SpatialKind.POSTURE:
		return true
	if not visuals_enabled:
		return false
	# El efecto del pool es el aviso de verdad; la malla de WP-19 es el respaldo
	# de los bancos sin `VFXPool`. Nunca se encienden los dos a la vez.
	if _begin_vfx():
		return true
	match _kind:
		TelegraphProfile.SpatialKind.DECAL_ZONE:
			if _ring == null:
				return false
			_ring.visible = true
			_update_ring(0.0)
		TelegraphProfile.SpatialKind.GUIDE_LINE, TelegraphProfile.SpatialKind.PARABOLA:
			if _guide == null:
				return false
			_guide.visible = true
			_update_guide(0.0)
		TelegraphProfile.SpatialKind.COLUMN:
			if _column == null:
				return false
			_column.visible = true
			_update_column(0.0)
		_:
			return false
	return true


## Avanza la señal espacial con el progreso [param t] del windup.
func _tick_spatial(t: float) -> void:
	if _vfx != null:
		_tick_vfx(t)
		return
	if _ring != null and _ring.visible:
		_update_ring(t)
	if _guide != null and _guide.visible:
		_update_guide(t)
	if _column != null and _column.visible:
		_update_column(t)


## Reposiciona y reescala el anillo de suelo según el progreso [param t].
func _update_ring(t: float) -> void:
	var centre := _ground_point if _has_ground_point else \
			(enemy.global_position if enemy != null else global_position)
	_ring.global_position = Vector3(centre.x, centre.y + RING_LIFT, centre.z)
	_ring.global_basis = Basis.IDENTITY
	# El anillo crece del `decal_grow_from` del perfil al radio completo: el
	# jugador ve el borde acercarse y sabe cuánto le queda. El EMP arranca en 0
	# (`docs/07` §5.8) y el pisotón en 0.25, para que se lea desde el principio.
	var from := _profile.decal_grow_from if _profile != null else 0.25
	var radius := maxf(_radius * lerpf(from, 1.0, t), 0.5)
	_ring_mesh.outer_radius = radius
	_ring_mesh.inner_radius = radius * (1.0 - RING_THICKNESS)
	_ring_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.35 + 0.30 * t)


## Dibuja la línea guía (o la parábola) de la cabeza al objetivo.
func _update_guide(t: float) -> void:
	var from := _head.global_position if _head != null else global_position
	var to := _guide_target if _has_guide_target else _ground_point
	_guide_mesh.clear_surfaces()
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _guide_material)
	if _kind == TelegraphProfile.SpatialKind.PARABOLA:
		for index: int in PARABOLA_SEGMENTS + 1:
			var ratio := float(index) / float(PARABOLA_SEGMENTS)
			var point := from.lerp(to, ratio)
			# Arco de altura proporcional al alcance, que es la forma que tendrá
			# el vuelo balístico de `ProceduralLegRig.begin_leap`.
			point.y += sin(PI * ratio) * from.distance_to(to) * 0.28
			_guide_mesh.surface_add_vertex(point)
	else:
		_guide_mesh.surface_add_vertex(from)
		_guide_mesh.surface_add_vertex(to)
	_guide_mesh.surface_end()
	_guide.global_transform = Transform3D.IDENTITY
	_guide_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.45 + 0.45 * t)


## Levanta la columna vertical sobre el objetivo del asedio.
func _update_column(t: float) -> void:
	var centre := _guide_target if _has_guide_target else _ground_point
	_column.global_position = Vector3(centre.x, centre.y + COLUMN_HEIGHT * 0.5, centre.z)
	_column.global_basis = Basis.IDENTITY
	_column_mesh.top_radius = COLUMN_RADIUS
	_column_mesh.bottom_radius = COLUMN_RADIUS * lerpf(0.4, 1.0, t)
	_column_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.20 + 0.30 * t)


# --------------------------------------------------------------------------
# Señal espacial servida por `VFXPool` (WP-26, `docs/13` §4 y §11 #12)
# --------------------------------------------------------------------------

## Pide al pool el efecto que le toca a [member _kind]. Devuelve `false` si no
## hay pool o si el efecto no se pudo servir, y entonces [method _begin_spatial]
## cae en la malla de respaldo de WP-19.
func _begin_vfx() -> bool:
	_release_vfx()
	_pool = VFXPool.resolve(self)
	if _pool == null:
		return false
	_vfx_id = _vfx_id_for_kind()
	if _vfx_id == &"":
		return false
	var centre := _spatial_centre()
	_vfx = _pool.request(_vfx_id, Transform3D(Basis.IDENTITY, centre))
	if _vfx == null:
		# Las telegrafías tienen pool dedicado y cero emisores (`docs/13` §11 #12),
		# así que un `null` acá no puede ser falta de presupuesto: sólo puede ser
		# que otro enemigo tenga ese mismo aviso en marcha. En ese caso se cae en
		# la malla de WP-19, que es fea pero existe; quedarse sin señal espacial no
		# es una opción.
		_vfx_id = &""
		return false
	_setup_vfx(centre)
	_tick_vfx(0.0)
	return true


## Id de [VFXPool] del tipo de señal en curso.
func _vfx_id_for_kind() -> StringName:
	match _kind:
		TelegraphProfile.SpatialKind.DECAL_ZONE:
			# La zona que nace en el centro es una onda que se expande (el EMP);
			# la que nace ya legible es una zona de la que hay que salir (el
			# pisotón). Lo dice `decal_grow_from` (`docs/07` §5.4 y §5.8).
			var grows_from_zero := _profile != null and _profile.decal_grow_from <= 0.001
			return VFX_RING if grows_from_zero else VFX_STOMP
		TelegraphProfile.SpatialKind.GUIDE_LINE:
			return VFX_GUIDE
		TelegraphProfile.SpatialKind.PARABOLA:
			return VFX_PARABOLA
		TelegraphProfile.SpatialKind.COLUMN:
			return VFX_COLUMN
	return &""


## Deja el efecto recién servido con su radio, su color y su reloj.
func _setup_vfx(centre: Vector3) -> void:
	var zone := _vfx as VFXDecalZone
	if zone != null:
		zone.set_radius(_radius)
		zone.set_ground_point(centre)
		return
	var ring := _vfx as VFXRing
	if ring != null:
		ring.set_radius(_radius)
		ring.set_ground_point(centre)
		# El crecimiento del anillo es suyo, no del tick del aviso: tiene que
		# llegar a los 45 m exactamente cuando sale el pulso, aunque el jefe
		# pierda el objetivo a mitad del windup (`docs/13` §4).
		ring.grow(_duration)
		return
	var beam := _vfx as VFXBeam
	if beam != null:
		beam.set_endpoints(centre, centre + Vector3.UP * COLUMN_HEIGHT)
		return
	var guide := _vfx as VFXGuide
	if guide != null and _profile != null:
		guide.set_width(_profile.guide_width)


## Avanza el efecto con el progreso [param t] del windup.
func _tick_vfx(t: float) -> void:
	if _vfx == null or not is_instance_valid(_vfx):
		return
	var centre := _spatial_centre()
	var zone := _vfx as VFXDecalZone
	if zone != null:
		zone.set_ground_point(centre)
		return
	var ring := _vfx as VFXRing
	if ring != null:
		ring.set_ground_point(centre)
		return
	var beam := _vfx as VFXBeam
	if beam != null:
		beam.set_endpoints(centre, centre + Vector3.UP * COLUMN_HEIGHT)
		return
	var guide := _vfx as VFXGuide
	if guide != null:
		var from := _head.global_position if _head != null else global_position
		guide.set_endpoints(from, _guide_target if _has_guide_target else _ground_point)
		guide.set_progress(t)


## Devuelve el efecto al pool. Es idempotente.
func _release_vfx() -> void:
	if _pool != null and _vfx != null and is_instance_valid(_vfx):
		_pool.release(_vfx)
	_vfx = null
	_vfx_id = &""


## Devuelve la señal espacial al pool si el aviso sale del árbol antes de
## terminar el fundido.
##
## [method _shutdown] sólo corre al final de los [constant FADE_SECONDS], y un
## enemigo que muere —o un nivel que se descarga— en pleno windup no llega ahí:
## el decal del pisotón o el anillo del EMP se quedaban con su ranura hasta la red
## del pool. Va por `_notification` y no por `_exit_tree` por la misma razón que en
## [SweepAction]: así sigue funcionando si alguna subclase futura sobrescribe
## `_exit_tree` sin llamar al `super`.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_release_vfx()


## Efecto de la señal espacial en curso, o `null`. Lo leen los checks y
## `ActionStomp` para congelar la zona.
func spatial_effect() -> Node3D:
	return _vfx if _vfx != null and is_instance_valid(_vfx) else null


## Congela la zona del pisotón en su sitio y, con [param strike], la cambia por la
## marca de cráter. Sin efecto del pool no hace nada: la malla de respaldo no
## tiene marca que dejar.
func freeze_zone(strike: bool = false) -> void:
	var zone := _vfx as VFXDecalZone
	if zone == null:
		return
	zone.freeze()
	if not strike:
		return
	zone.strike()
	# El cráter dura cuatro segundos más que el aviso, así que el efecto deja de
	# ser del aviso y pasa a ser del pool: entregarlo acá es lo que hace que la
	# marca sobreviva al `_shutdown` de los tres canales sin quedarse con la
	# ranura para siempre.
	if _pool != null:
		_pool.release_when_done(_vfx)
	_vfx = null
	_vfx_id = &""


## Dispara el destello del anillo del EMP cuando el pulso sale de verdad.
func flash_ring() -> void:
	var ring := _vfx as VFXRing
	if ring == null:
		return
	ring.flash()
	# El destello dura 0.3 s y el apagado de los canales llega a los 0.15: el
	# anillo pasa a ser del pool para que no se lo corte a la mitad.
	if _pool != null:
		_pool.release_when_done(_vfx)
	_vfx = null
	_vfx_id = &""


## Centro de la señal espacial: el punto de suelo fijado, o el enemigo.
func _spatial_centre() -> Vector3:
	if _kind == TelegraphProfile.SpatialKind.COLUMN and _has_guide_target:
		return _guide_target
	if _has_ground_point:
		return _ground_point
	return enemy.global_position if enemy != null else global_position


# --------------------------------------------------------------------------
# Construcción de los canales
# --------------------------------------------------------------------------

## Crea la luz, las tres señales espaciales y el reproductor si la escena no los
## trae ya.
func _build_channels() -> void:
	_light = get_node_or_null(^"ChargeLight") as OmniLight3D
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "ChargeLight"
		add_child(_light)
	_light.omni_range = LIGHT_RANGE
	_light.light_color = REST_COLOR
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	_light.top_level = true

	_ring = get_node_or_null(^"GroundRing") as MeshInstance3D
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.name = "GroundRing"
		add_child(_ring)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = DEFAULT_RADIUS * (1.0 - RING_THICKNESS)
	_ring_mesh.outer_radius = DEFAULT_RADIUS
	_ring_material = _unshaded_material(REST_COLOR)
	_ring_mesh.material = _ring_material
	_ring.mesh = _ring_mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	_ring.top_level = true

	_guide = get_node_or_null(^"GuideLine") as MeshInstance3D
	if _guide == null:
		_guide = MeshInstance3D.new()
		_guide.name = "GuideLine"
		add_child(_guide)
	_guide_mesh = ImmediateMesh.new()
	_guide_material = _unshaded_material(REST_COLOR)
	_guide_material.vertex_color_use_as_albedo = false
	_guide.mesh = _guide_mesh
	_guide.material_override = _guide_material
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.visible = false
	_guide.top_level = true

	_column = get_node_or_null(^"SiegeColumn") as MeshInstance3D
	if _column == null:
		_column = MeshInstance3D.new()
		_column.name = "SiegeColumn"
		add_child(_column)
	_column_mesh = CylinderMesh.new()
	_column_mesh.height = COLUMN_HEIGHT
	_column_mesh.top_radius = COLUMN_RADIUS
	_column_mesh.bottom_radius = COLUMN_RADIUS
	_column_mesh.radial_segments = 12
	_column_mesh.rings = 1
	_column_material = _unshaded_material(REST_COLOR)
	_column_mesh.material = _column_material
	_column.mesh = _column_mesh
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	_column.top_level = true

	_audio = get_node_or_null(^"ChargeAudio") as AudioStreamPlayer3D
	if _audio == null:
		_audio = AudioStreamPlayer3D.new()
		_audio.name = "ChargeAudio"
		add_child(_audio)
	_audio.unit_size = AUDIO_UNIT_SIZE
	_audio.max_distance = 0.0
	_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	if AudioServer.get_bus_index(String(AUDIO_BUS)) >= 0:
		_audio.bus = String(AUDIO_BUS)
	_audio.stream = _stream_for(&"charge")


## Material aditivo sin sombreado, el que usan las tres señales espaciales.
func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	return material


## Evento de audio del perfil, o el barrido genérico.
func _audio_event() -> StringName:
	if _profile != null and _profile.audio_event != &"":
		return _profile.audio_event
	return &"charge"


## Carga (y cachea) el sonido de [param event]. Sin archivo cae en `charge.wav`,
## para que un banco incompleto no deje al aviso sin canal de audio.
func _stream_for(event: StringName) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var path := "res://assets/audio/enemies/%s.wav" % event
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path, "AudioStream") as AudioStream
	elif event != &"charge" and ResourceLoader.exists(CHARGE_STREAM):
		stream = ResourceLoader.load(CHARGE_STREAM, "AudioStream") as AudioStream
	_streams[event] = stream
	return stream


## Energía relativa de la luz en el progreso [param t]. Crece con el cuadrado:
## el último cuarto del windup es el que se ve, que es justo cuando el jugador
## tiene que decidir la esquiva.
func _energy_ramp(t: float) -> float:
	var from := _profile.light_energy_from if _profile != null else 0.2
	var to := _profile.light_energy_to if _profile != null else 1.0
	return from + (to - from) * t * t


## Resuelve la cabeza la primera vez que hace falta. No se puede hacer en
## `_ready()`: el de este nodo corre **antes** que el de [EnemyBase], que es
## quien construye el grafo de partes.
func _ensure_head() -> void:
	if _head != null and is_instance_valid(_head):
		return
	_head = _resolve_head()


## Malla de la cabeza del enemigo, donde se planta la luz de carga.
func _resolve_head() -> Node3D:
	if enemy == null or not enemy.has_method(&"get_part"):
		return enemy
	for part_name: StringName in [&"wp_head_visor", &"hull"]:
		var part := enemy.call(&"get_part", part_name) as EnemyPart
		if part != null and part.mesh != null:
			return part.mesh
	return enemy


## Tiñe los emisivos de la cabeza con [param color], guardando los originales
## para poder restaurarlos en [method _shutdown].
func _tint_head(color: Color) -> void:
	if _head == null:
		return
	var mesh_instance := _head as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	if _tinted.is_empty():
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or not source.emission_enabled:
				continue
			var current := mesh_instance.get_surface_override_material(surface) as BaseMaterial3D
			if current == null:
				current = source.duplicate() as BaseMaterial3D
				mesh_instance.set_surface_override_material(surface, current)
			_tinted.append({"material": current, "emission": current.emission})
	for entry: Dictionary in _tinted:
		(entry["material"] as BaseMaterial3D).emission = color


## Apaga los canales y devuelve los emisivos a su color original.
func _shutdown() -> void:
	_release_vfx()
	if _light != null:
		_light.visible = false
		_light.light_energy = 0.0
	if _ring != null:
		_ring.visible = false
	if _guide != null:
		_guide.visible = false
		_guide_mesh.clear_surfaces()
	if _column != null:
		_column.visible = false
	for entry: Dictionary in _tinted:
		(entry["material"] as BaseMaterial3D).emission = entry["emission"] as Color
	_tinted.clear()
	_channels = 0
	_has_guide_target = false
