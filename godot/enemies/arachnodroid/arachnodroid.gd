## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Arachnodroid, el jefe del MVP (`docs/07`).
##
## [b]No agrega clases nuevas[/b]: es configuración de [EnemyBase] más un
## [EnemyAction] por ataque. Este script sólo cablea lo que es exclusivamente
## suyo y no cabe en el guion declarativo de fases de `docs/06` §6.1:
##
## 1. [b]Apertura de la carcasa en P4[/b] (`docs/07` §6): la `carapace` rota
##    [constant CARAPACE_ANGLE]° sobre su bisagra trasera en
##    [constant CARAPACE_SECONDS] s, malla y colisionador juntos —el
##    `AnimatableBody3D` cuelga de la malla, así que viaja con ella—, y el cono de
##    los tres `wp_core_*` se abre a [constant OPEN_CONE_HALF_ANGLE]°.
## 2. [b]Sensor de respaldo del visor[/b] (`docs/07` §4 y §9): romperlo ciega la
##    percepción 20 s y bloquea `head_laser` 30 s —eso lo hace el `on_destroy`
##    declarativo—, pero a los [constant BACKUP_SENSOR_SECONDS] s del impacto
##    entra en línea el sensor de respaldo y la percepción vuelve a la nominal.
## 3. [b]Autodestrucción de P5[/b] (`docs/07` §6): [constant SELFDESTRUCT_SECONDS]
##    s de cuenta atrás con el emisivo blanco pulsando cada vez más rápido y
##    [signal selfdestruct_tick] sincronizado con él; al expirar,
##    [method detonate] reparte [constant DETONATION_DAMAGE] entre los edificios
##    a ≤ [constant DETONATION_RADIUS] m. Si el jugador rompe el tercer núcleo
##    antes, el jefe cae sin detonar: eso ya lo resuelve el `_check_defeat` de
##    [EnemyBase], y acá sólo hay que parar el reloj.
##
## [b]Todo por acumulador[/b], nunca con [Timer] (`docs/00` §6): así la cuenta
## atrás respeta `Engine.time_scale` y los checks pueden acelerar la simulación.
class_name Arachnodroid extends EnemyBase

## Arrancó la cuenta atrás de la autodestrucción.
signal selfdestruct_started(seconds: float)

## Tic de la cuenta atrás, a ritmo creciente.
signal selfdestruct_tick(remaining: float)

## La carcasa terminó de abrirse.
signal carapace_opened()

## Id de fase en la que arranca la autodestrucción (`docs/07` §6).
const SELFDESTRUCT_PHASE: StringName = &"p5_selfdestruct"

## Id de la fase del vientre, en la que se abre la carcasa (`docs/07` §6).
const BELLY_PHASE: StringName = &"p4_belly"

## Duración de la cuenta atrás, en segundos (`docs/07` §6).
const SELFDESTRUCT_SECONDS: float = 45.0

## Duración de la cuenta atrás cuando la dispara el estado `DOWNED`, en segundos
## (WP-19b).
##
## Más larga que los 45 s de P5 porque no es lo mismo: los 45 s son el jefe
## [b]decidiendo[/b] inmolarse con dos núcleos rotos, y estos 90 son el sistema
## sobrecargado de un coloso al que le arrancaron las cuatro patas. Lo que
## garantizan es que la ronda [b]siempre termina[/b]: sin esto, un jefe caído se
## queda tumbado para siempre y la partida no se puede ni ganar ni perder
## (medido en WP-23).
const SELFDESTRUCT_SECONDS_DOWNED: float = 90.0

## Daño total que reparte la detonación entre los edificios cercanos.
const DETONATION_DAMAGE: float = 25000.0

## Radio de la detonación, en metros (`docs/07` §6).
const DETONATION_RADIUS: float = 120.0

## Sacudida de cámara de la detonación.
const DETONATION_TRAUMA: float = 1.0

## Parte que se abre en P4.
const CARAPACE_PART: StringName = &"carapace"

## Vientre: cuelga de la carcasa en el GLB y hospeda a los tres núcleos.
const UNDERBELLY_PART: StringName = &"underbelly"

## Ángulo de apertura de la carcasa, en grados (`docs/07` §6 y §15 riesgo 5).
const CARAPACE_ANGLE: float = 70.0

## Segundos que tarda en abrirse.
const CARAPACE_SECONDS: float = 1.5

## Semiapertura del cono de los núcleos con la carcasa abierta, en grados
## (`docs/07` §4: 110° de apertura).
const OPEN_CONE_HALF_ANGLE: float = 55.0

## Punto débil del visor.
const VISOR_ID: StringName = &"wp_head_visor"

## Segundos tras romper el visor a los que entra el sensor de respaldo
## (`docs/07` §4 y §9).
const BACKUP_SENSOR_SECONDS: float = 45.0

## Ids de los tres núcleos ventrales.
const CORE_IDS: Array[StringName] = [&"wp_core_a", &"wp_core_b", &"wp_core_c"]

## Frecuencia del pulso blanco al empezar y al acabar la cuenta atrás, en Hz
## (`docs/07` §10, `selfdestruct_tick`).
const TICK_HZ_RANGE: Vector2 = Vector2(1.0, 6.0)

## Energía del emisivo blanco en el valle y en la cresta del pulso.
const PULSE_ENERGY_RANGE: Vector2 = Vector2(0.6, 6.0)

var _selfdestruct_left: float = -1.0
var _selfdestruct_running: bool = false
var _detonated: bool = false
var _tick_phase: float = 0.0
var _ticks: int = 0
var _selfdestruct_total: float = SELFDESTRUCT_SECONDS
var _downed_selfdestruct: bool = false
var _was_downed: bool = false

var _carapace_t: float = 1.0
var _carapace_opening: bool = false
var _carapace_rest: Transform3D = Transform3D.IDENTITY
var _carapace_pivot: Vector3 = Vector3.ZERO
var _carapace_ready: bool = false
var _underbelly_rest: Transform3D = Transform3D.IDENTITY
var _has_underbelly: bool = false

var _visor_timer: float = -1.0
var _backup_sensor_done: bool = false
var _pulse_materials: Array[BaseMaterial3D] = []


func _ready() -> void:
	super._ready()
	var _phase := phase_changed.connect(_on_phase_changed)
	var visor := get_weak_point(VISOR_ID)
	if visor != null:
		var _broken := visor.destroyed.connect(_on_visor_destroyed)


## Lleva los cuatro acumuladores propios del jefe. Ninguno usa un [Timer].
##
## Con [member Global.debug_freeze_ai] no avanza nada (`docs/11` §11): un jefe
## congelado no puede detonar por debajo mientras el check inyecta hechos por el
## bus.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if delta <= 0.0 or Global.debug_freeze_ai:
		return
	PerfProbe.begin(&"enemy_base")
	_tick_downed_state()
	_tick_carapace(delta)
	_tick_backup_sensor(delta)
	_tick_selfdestruct(delta)
	PerfProbe.end(&"enemy_base")


# --------------------------------------------------------------------------
# Interfaz pública (`docs/07` §11)
# --------------------------------------------------------------------------

## Segundos que faltan para la detonación, o `-1.0` si P5 no empezó.
func selfdestruct_remaining() -> float:
	return _selfdestruct_left


## `true` mientras corre la cuenta atrás.
func is_selfdestructing() -> bool:
	return _selfdestruct_running


## Tics de la cuenta atrás emitidos hasta ahora.
func selfdestruct_ticks() -> int:
	return _ticks


## Duración total de la cuenta atrás en curso: 45 s por dos núcleos rotos, 90 s
## si la disparó el estado `DOWNED`.
func selfdestruct_total() -> float:
	return _selfdestruct_total


## `true` si la cuenta atrás la disparó el desplome y no los núcleos.
func is_downed_selfdestruct() -> bool:
	return _downed_selfdestruct


## Materiales emisivos de carcasa que el pulso blanco de P5 está modulando.
##
## Son los que `EnemyBase._apply_phase_emissive` recoloreó al entrar en la fase,
## y salen de las superficies que el importador marcó con `has_emissive_surface`
## (`docs/05` §9.2). Si el modelo no trae ninguna fuera de los puntos débiles,
## esto vale 0 y el pulso no tiene dónde verse: es una observación del
## `arachnodroid_check`, no un fallo del jefe.
func pulse_material_count() -> int:
	return _pulse_materials.size()


## Detona el jefe: [constant DETONATION_DAMAGE] repartidos entre los edificios a
## ≤ [constant DETONATION_RADIUS] m, sacudida máxima y derrota (`docs/07` §6).
##
## El jefe [b]muere igual[/b]; lo que decide victoria o derrota es la integridad
## de la ciudad (`docs/11`). Es idempotente: [method EnemyBase.declare_defeat] ya
## garantiza una sola emisión de `defeated`, y la guarda de acá evita además que
## el reparto de daño se cobre dos veces.
func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_selfdestruct_running = false
	_selfdestruct_left = 0.0

	var targets := _buildings_in_radius(DETONATION_RADIUS)
	if not targets.is_empty():
		var share := DETONATION_DAMAGE / float(targets.size())
		for building: Node3D in targets:
			var _applied: Variant = building.call(&"take_damage", share, global_position)
	Events.camera_trauma.emit(DETONATION_TRAUMA, global_position)
	var rig_audio := get_node_or_null(^"AudioRig") as AudioRig
	if rig_audio != null:
		var _player := rig_audio.play(&"emp_burst", global_position)
	declare_defeat()


## Destino forzado de la marcha (`docs/06` §10.1, clave `march_goal`).
##
## Devuelve `null` salvo en P5, donde el jefe deja de elegir objetivo y corre al
## [b]centro de la ciudad[/b] con el reloj encima. El centro se calcula como el
## baricentro de los edificios vivos, que para la retícula rectangular del
## `CityGrid` (`docs/10` §4) es su centro exacto y además no obliga a este nodo a
## conocer al `CityGrid`.
func march_goal() -> Variant:
	if not _selfdestruct_running:
		return null
	return city_centre()


## Baricentro de los edificios vivos, o la posición propia si no queda ninguno.
func city_centre() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return global_position
	var total := Vector3.ZERO
	var count := 0
	for node: Node in tree.get_nodes_in_group(&"buildings"):
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		if building.has_method(&"is_destroyed") and bool(building.call(&"is_destroyed")):
			continue
		total += building.global_position
		count += 1
	if count == 0:
		return global_position
	return total / float(count)


## Progreso de la apertura de la carcasa, de 0 (cerrada) a 1 (abierta).
func carapace_progress() -> float:
	return _carapace_t


## `true` si la carcasa ya terminó de abrirse.
func is_carapace_open() -> bool:
	return _carapace_ready and _carapace_t >= 1.0


## Ángulo de apertura vigente de la carcasa, en grados.
func carapace_angle() -> float:
	return CARAPACE_ANGLE * _smooth(_carapace_t)


## Segundos que faltan para que entre el sensor de respaldo, o `-1.0` si el visor
## sigue entero o el respaldo ya entró (`docs/07` §9).
func backup_sensor_remaining() -> float:
	if _visor_timer < 0.0:
		return -1.0
	return maxf(0.0, BACKUP_SENSOR_SECONDS - _visor_timer)


## `true` si el sensor de respaldo ya devolvió la percepción a la nominal.
func backup_sensor_online() -> bool:
	return _backup_sensor_done


# --------------------------------------------------------------------------
# Desplome (WP-19b)
# --------------------------------------------------------------------------

## Detecta el paso a `DOWNED` y aplica el estado final del jefe.
##
## Con las cuatro patas perdidas el coloso ya no es un enemigo: es un blanco
## inmóvil con una cuenta atrás encima. Tres cosas, en este orden:
##
## 1. La carcasa se abre —si no lo había hecho ya en P4— para que el vientre
##    quede a la vista.
## 2. Los tres `wp_core_*` pasan a [b]exposición permanente[/b]: sin las tres
##    rodillas de `AFTER_PARTS` ni el cono de 55°, que con el cuerpo tumbado no
##    se puede satisfacer desde ningún lado. `pierces_host` sigue actuando, así
##    que el disparo atraviesa el collider de la panza.
## 3. Arranca la autodestrucción de [constant SELFDESTRUCT_SECONDS_DOWNED]. Si
##    P5 ya venía corriendo, [b]conserva el tiempo que le quedaba[/b].
func _tick_downed_state() -> void:
	if _was_downed or not is_downed():
		return
	_was_downed = true
	_open_carapace()
	_expose_cores_always()
	if not _selfdestruct_running and not _detonated:
		_downed_selfdestruct = true
		_force_selfdestruct_phase()


## Pone los tres núcleos en `ALWAYS`.
##
## El [WeakPointProfile] se **duplica** antes de tocarlo, igual que en
## [method _widen_core_cone]: es un recurso cargado y compartido, y escribirle
## encima ensuciaría la caché de `ResourceLoader` para la ronda siguiente.
func _expose_cores_always() -> void:
	for core_id: StringName in CORE_IDS:
		var weak_point := get_weak_point(core_id)
		if weak_point == null or weak_point.profile == null:
			continue
		var copy := weak_point.profile.duplicate() as WeakPointProfile
		copy.conditions = [WeakPoint.Exposure.ALWAYS]
		copy.require_all = true
		weak_point.profile = copy
	_refresh_weak_points()


## Fuerza la entrada en `p5_selfdestruct` sin esperar a los dos núcleos.
##
## Se entra por [method EnemyBase._enter_phase], no tocando las condiciones: así
## se aplican los mismos `lock_attacks` —queda sólo `shake_off`—, los mismos
## multiplicadores y el mismo emisivo blanco que por la vía normal, y
## `_evaluate_phases()` no puede retroceder porque P5 es el índice más alto.
func _force_selfdestruct_phase() -> void:
	if profile == null:
		return
	for index: int in profile.phases.size():
		if StringName(profile.phases[index].get("id", &"")) != SELFDESTRUCT_PHASE:
			continue
		if current_phase_index() < index:
			_enter_phase(index)
		elif not _selfdestruct_running:
			# Ya estábamos en P5 pero con la cuenta parada: la arrancamos igual.
			_start_selfdestruct(SELFDESTRUCT_SECONDS_DOWNED)
		return


# --------------------------------------------------------------------------
# Fases (`docs/07` §6)
# --------------------------------------------------------------------------

## Aplica lo que el bloque `then` de la fase declara y [EnemyBase] no sabe hacer.
##
## Las claves extra (`open_carapace`, `core_cone_half_angle`,
## `selfdestruct_seconds`) viajan en el mismo diccionario que los multiplicadores
## y los desbloqueos: [EnemyBase] las ignora sin ruido y las lee quien sabe qué
## significan, que es este script.
func _on_phase_changed(phase_id: StringName) -> void:
	var effects := _phase_effects()
	if bool(effects.get("open_carapace", phase_id == BELLY_PHASE)):
		_open_carapace()
	if effects.has("core_cone_half_angle"):
		_widen_core_cone(float(effects["core_cone_half_angle"]))
	elif phase_id == BELLY_PHASE:
		_widen_core_cone(OPEN_CONE_HALF_ANGLE)
	if phase_id == SELFDESTRUCT_PHASE:
		_start_selfdestruct(float(effects.get("selfdestruct_seconds",
				SELFDESTRUCT_SECONDS)))


## Bloque `then` de la fase actual.
func _phase_effects() -> Dictionary:
	if profile == null:
		return {}
	var index := current_phase_index()
	if index < 0 or index >= profile.phases.size():
		return {}
	return profile.phases[index].get("then", {}) as Dictionary


# --------------------------------------------------------------------------
# Carcasa (`docs/07` §6, P4)
# --------------------------------------------------------------------------

## Mide la bisagra trasera de la carcasa y arranca la rotación.
func _open_carapace() -> void:
	if _carapace_opening or _carapace_ready:
		return
	var part := get_part(CARAPACE_PART)
	if part == null or part.mesh == null or not is_instance_valid(part.mesh):
		return
	if part.is_detached():
		return
	_carapace_rest = part.mesh.transform
	# La bisagra es el borde **trasero** de la caja de la malla: en Godot `-Z` es
	# el frente, así que el borde de atrás es el `+Z` del AABB local. Rotando
	# sobre él, el frente de la carcasa se levanta y el vientre queda a la vista.
	var box := part.mesh.get_aabb()
	var hinge_local := Vector3(box.position.x + box.size.x * 0.5,
			box.position.y + box.size.y * 0.5, box.position.z + box.size.z)
	_carapace_pivot = _carapace_rest * hinge_local
	# El vientre cuelga de la carcasa en el GLB (`docs/05` §4.4), así que
	# rotarla se lo llevaría con ella y el cono de los núcleos —que mira hacia
	# abajo en espacio local del hospedador (`docs/06` §5)— quedaría apuntando
	# 70° torcido, justo cuando el jugador tiene que poder meterse debajo. Se
	# guarda su pose de reposo para dejárselo quieto en cada tick.
	var belly := get_part(UNDERBELLY_PART)
	_underbelly_rest = Transform3D.IDENTITY
	_has_underbelly = belly != null and belly.mesh != null and is_instance_valid(belly.mesh) \
			and belly.mesh.get_parent() == part.mesh
	if _has_underbelly:
		_underbelly_rest = belly.mesh.transform
	_carapace_t = 0.0
	_carapace_opening = true


## Avanza la apertura. La malla se lleva a su `AnimatableBody3D` hijo, así que el
## colisionador se abre con ella y el vientre queda alcanzable de verdad.
func _tick_carapace(delta: float) -> void:
	if not _carapace_opening:
		return
	var part := get_part(CARAPACE_PART)
	if part == null or part.mesh == null or not is_instance_valid(part.mesh) \
			or part.is_detached():
		_carapace_opening = false
		return
	_carapace_t = minf(1.0, _carapace_t + delta / maxf(CARAPACE_SECONDS, 0.01))
	var rotation_basis := Basis(Vector3.RIGHT, deg_to_rad(carapace_angle()))
	part.mesh.transform = Transform3D(rotation_basis,
			_carapace_pivot - rotation_basis * _carapace_pivot) * _carapace_rest
	# El vientre se queda donde estaba: `C(t) · U(t) = C₀ · U₀`, o sea
	# `U(t) = C(t)⁻¹ · C₀ · U₀`. Sólo se abre la tapa.
	if _has_underbelly:
		var belly := get_part(UNDERBELLY_PART)
		if belly != null and belly.mesh != null and is_instance_valid(belly.mesh):
			belly.mesh.transform = part.mesh.transform.affine_inverse() \
					* _carapace_rest * _underbelly_rest
	if _carapace_t < 1.0:
		return
	_carapace_opening = false
	_carapace_ready = true
	carapace_opened.emit()


## Suavizado de la apertura: arranca y termina despacio.
func _smooth(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


## Abre el cono de exposición de los tres núcleos a [param half_angle]°.
##
## El [WeakPointProfile] se [b]duplica[/b] antes de tocarlo: es un recurso
## cargado y compartido, y escribirle encima ensuciaría la caché de
## `ResourceLoader` para la ronda siguiente y para el `.tres` del disco.
func _widen_core_cone(half_angle: float) -> void:
	for core_id: StringName in CORE_IDS:
		var weak_point := get_weak_point(core_id)
		if weak_point == null or weak_point.profile == null:
			continue
		if is_equal_approx(weak_point.profile.cone_half_angle, half_angle):
			continue
		var copy := weak_point.profile.duplicate() as WeakPointProfile
		copy.cone_half_angle = half_angle
		weak_point.profile = copy
	_refresh_weak_points()


# --------------------------------------------------------------------------
# Sensor de respaldo del visor (`docs/07` §4 y §9)
# --------------------------------------------------------------------------

## Arranca el reloj del respaldo. La ceguera de 20 s y el bloqueo de 30 s de
## `head_laser` ya los aplicó el `on_destroy` declarativo de [EnemyBase].
func _on_visor_destroyed(_weak_point_id: StringName) -> void:
	if _visor_timer >= 0.0:
		return
	_visor_timer = 0.0
	_backup_sensor_done = false


## A los 45 s del impacto, la percepción vuelve a la nominal.
func _tick_backup_sensor(delta: float) -> void:
	if _visor_timer < 0.0 or _backup_sensor_done:
		return
	_visor_timer += delta
	if _visor_timer < BACKUP_SENSOR_SECONDS:
		return
	_backup_sensor_done = true
	if perception != null and perception.has_method(&"restore_sight"):
		perception.call(&"restore_sight")


# --------------------------------------------------------------------------
# Autodestrucción (`docs/07` §6, P5)
# --------------------------------------------------------------------------

## Arranca la cuenta atrás y cachea los emisivos que van a pulsar.
func _start_selfdestruct(seconds: float) -> void:
	if _selfdestruct_running or _detonated:
		return
	_selfdestruct_left = SELFDESTRUCT_SECONDS_DOWNED if _downed_selfdestruct 			else maxf(seconds, 0.0)
	_selfdestruct_total = maxf(_selfdestruct_left, 0.01)
	_selfdestruct_running = true
	_tick_phase = 0.0
	_ticks = 0
	_collect_pulse_materials()
	selfdestruct_started.emit(_selfdestruct_left)


## Descuenta el reloj, pulsa el emisivo blanco a ritmo creciente y detona.
##
## El tic y el pulso comparten fase a propósito (`docs/07` §10): el destello y el
## sonido son el mismo evento, de 1 Hz al principio a 6 Hz al final, y eso es lo
## que convierte la barra de tiempo en algo que se oye sin mirar el HUD.
func _tick_selfdestruct(delta: float) -> void:
	if not _selfdestruct_running:
		return
	if is_defeated():
		# El tercer núcleo cayó antes de que expirara el reloj: el jefe muere sin
		# detonar (`docs/07` §6).
		_selfdestruct_running = false
		_selfdestruct_left = -1.0
		_restore_pulse_materials()
		return

	_selfdestruct_left = maxf(0.0, _selfdestruct_left - delta)
	var ratio := 1.0 - _selfdestruct_left / _selfdestruct_total
	var hz := lerpf(TICK_HZ_RANGE.x, TICK_HZ_RANGE.y, clampf(ratio, 0.0, 1.0))
	_tick_phase += delta * hz
	_apply_pulse()
	while _tick_phase >= 1.0:
		_tick_phase -= 1.0
		_ticks += 1
		selfdestruct_tick.emit(_selfdestruct_left)
		var rig_audio := get_node_or_null(^"AudioRig") as AudioRig
		if rig_audio != null:
			var _player := rig_audio.play(&"selfdestruct_tick", global_position,
					0.0, lerpf(0.9, 1.4, ratio))
	if _selfdestruct_left <= 0.0:
		detonate()


## Materiales emisivos de la carcasa que pulsan en blanco. Son los mismos que
## recolorea `EnemyBase._apply_phase_emissive`, que ya corrió al entrar en la
## fase: acá sólo se toman las referencias para modular su energía.
func _collect_pulse_materials() -> void:
	_pulse_materials.clear()
	for part: EnemyPart in get_parts():
		if not part.has_emissive_surface or part.weak_point_id != &"":
			continue
		if part.mesh == null or not is_instance_valid(part.mesh):
			continue
		for surface: int in part.mesh.get_surface_override_material_count():
			var material := part.mesh.get_surface_override_material(surface) as BaseMaterial3D
			if material != null and material.emission_enabled:
				_pulse_materials.append(material)


## Escribe la energía del pulso en los emisivos cacheados.
func _apply_pulse() -> void:
	if _pulse_materials.is_empty():
		return
	var wave := 0.5 - 0.5 * cos(_tick_phase * TAU)
	var energy := lerpf(PULSE_ENERGY_RANGE.x, PULSE_ENERGY_RANGE.y, wave)
	for material: BaseMaterial3D in _pulse_materials:
		material.emission_energy_multiplier = energy


## Deja el emisivo en reposo y suelta las referencias.
func _restore_pulse_materials() -> void:
	for material: BaseMaterial3D in _pulse_materials:
		material.emission_energy_multiplier = PULSE_ENERGY_RANGE.x
	_pulse_materials.clear()


## Edificios vivos a [param radius] metros o menos, con `take_damage`.
func _buildings_in_radius(radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return found
	for node: Node in tree.get_nodes_in_group(&"buildings"):
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		if not building.has_method(&"take_damage"):
			continue
		if building.has_method(&"is_destroyed") and bool(building.call(&"is_destroyed")):
			continue
		if building.global_position.distance_to(global_position) <= radius:
			found.append(building)
	return found
