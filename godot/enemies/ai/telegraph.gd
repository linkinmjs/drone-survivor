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
const LIGHT_LUMENS: float = 90000.0

## Alcance de la luz de carga, en metros.
const LIGHT_RANGE: float = 60.0

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
