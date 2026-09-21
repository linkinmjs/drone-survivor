## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Overlay de la señal FPV: viñeta, grano, scanlines, aberración, daño y EMP
## (`docs/13` §7; `docs/narrativa` §4).
##
## Es un [CanvasLayer] en la capa **−1** con un único hijo, `Rect`, un [ColorRect] de
## pantalla completa con el [ShaderMaterial] de `fpv_overlay.gdshader`. La capa importa
## y no es decorativa (`docs/12` §1.1):
##
## | Capa | Qué dibuja |
## |---|---|
## | −2 | compuesto del ojo de pez (`FPVCamera`) |
## | **−1** | **este overlay** |
## | 0 | `FlightHUD` |
##
## Es decir: el overlay procesa la imagen del dron —la lea de una `SubViewport` del ojo
## de pez o del render directo de la raíz— y el HUD de vuelo se dibuja **después**, sin
## viñeta, sin grano y sin corrimiento de color. El instrumental tiene que leerse
## nítido incluso con la señal reventada, que es de lo que habla `docs/13` §7.
##
## ## El overlay se alimenta solo
##
## Nadie le escribe los uniforms desde afuera; los dos que importan salen de dos
## fuentes distintas y por eso este nodo escucha las dos:
##
## - **`damage`** ← `Events.hull_changed(ratio)` como `1 − ratio`. Va por el **bus**
##   porque el casco publica su integridad para todo el que la quiera (`docs/09` §2.9).
## - **`emp`** ← [signal EnergySystem.emp_hit], que es una señal **local** y no del bus:
##   hay que ir a buscar al [EnergySystem] hermano y volver a engancharse después de
##   cada reaparición, exactamente como hace `CombatHUD._bind_energy_system`.
##
## El decaimiento del EMP es el mismo de [HUDGlitchLayer]: `e = restante / duración`,
## lineal de 1 a 0 en `glitch_seconds`, y un segundo pulso **reinicia** en vez de
## acumular. No es una coincidencia ni una copia: es la única forma de que el glitch de
## la imagen y el del HUD estén en fase sin sincronizar dos relojes (`docs/12` §4.3).
##
## ## Acumulador y reloj propio
##
## El shader **no** usa `TIME`: [method tick] avanza un uniform `time` con el delta del
## motor. Así `overlay_check` congela el reloj, lo adelanta a mano y mide el
## decaimiento en pasos exactos, y las capturas de `overlay_shots` son reproducibles.
## Es la misma decisión que tomó `hud/combat/static.gdshader` y por el mismo motivo.
##
## ## LOW no lee la pantalla
##
## `docs/13` §3.4 deja el overlay en «solo viñeta» en preset LOW. No alcanza con bajar
## uniforms: `hint_screen_texture` obliga a **copiar el backbuffer** aunque el shader no
## use la textura. Por eso hay dos materiales y [method set_full_quality] cambia el del
## rectángulo entero; el de LOW usa `fpv_overlay_low.gdshader`, que no tiene `screen_tex`.
class_name FPVOverlay extends CanvasLayer

## Capa de canvas del overlay (`docs/12` §1.1).
const LAYER: int = -1

## Shader del overlay completo.
const FULL_SHADER: String = "res://drone/fpv_camera/fpv_overlay.gdshader"

## Shader de «solo viñeta» del preset LOW.
const LOW_SHADER: String = "res://drone/fpv_camera/fpv_overlay_low.gdshader"

## Valores iniciales de los uniforms de identidad (`docs/13` §7 y §9).
const VIGNETTE_STRENGTH: float = 0.35
const NOISE_AMOUNT: float = 0.035
const SCANLINE_AMOUNT: float = 0.06
const SCANLINE_COUNT: float = 540.0
const ABERRATION_PX: float = 1.2

## Cada cuánto se repliega el reloj del shader, en segundos.
##
## Es un múltiplo exacto de **los cuatro periodos** que `fpv_overlay.gdshader` deriva
## de `time`: el latido de la viñeta (`PULSE_HZ` 1,5 → 2/3 s), el grano
## (`GRAIN_HZ` 24 → 1/24 s), los bloques del EMP (`EMP_BLOCK_HZ` 18 → 1/18 s) y la
## barra que recorre la pantalla (`EMP_BAR_SECONDS` 0,6 s). El mínimo común múltiplo
## de los cuatro es **6 s**, y 600 son cien de esos: en el repliegue, `sin(time·…)` y
## `fract(time/…)` valen exactamente lo mismo de los dos lados, así que no hay salto
## que ver. Los dos `floor(time·…)` son semillas de hash y cambian igual cada
## 1/18 y 1/24 de segundo.
##
## Sin esto, una sesión larga muestreaba `sin()` con seis cifras enteras y el latido
## de 1,5 Hz perdía fase contra sí mismo: el `float` de 32 bits del uniform deja de
## distinguir dos frames seguidos mucho antes que el `float` de 64 de GDScript. Es la
## misma red que [constant CameraRig.NOISE_WRAP].
const TIME_WRAP: float = 600.0

## Cuánto se lleva el daño de la calidad de señal, y cuánto el EMP.
##
## Son dos factores y no una resta porque miden cosas distintas: el daño **degrada** el
## enlace de forma permanente hasta que el taller entregue otro dron, y el EMP lo
## **interrumpe** mientras dura. Un dron con el casco al 40 % y un EMP encima tiene que
## quedar peor que cualquiera de las dos cosas por separado, que es lo que da el
## producto: `0,55 × 0,30 = 0,165`.
const DAMAGE_WEIGHT: float = 0.75
const EMP_WEIGHT: float = 0.7

var _rect: ColorRect = null
var _full_material: ShaderMaterial = null
var _low_material: ShaderMaterial = null
var _full: bool = true

var _damage: float = 0.0
var _emp: float = 0.0
var _emp_left: float = 0.0
var _emp_duration: float = 0.0
var _time: float = 0.0
var _emp_seed: float = 0.0

## El [EnergySystem] al que está enganchada [signal EnergySystem.emp_hit]. Se vuelve a
## resolver en cada reaparición.
var _energy: EnergySystem = null

## La cámara FPV del rig, para no pintar la señal del dron sobre una cámara que no es
## la suya (la cinemática de intro, la de reaparición, la de seguimiento).
var _fpv: Camera3D = null


func _ready() -> void:
	layer = LAYER
	_build_rect()
	_build_materials()
	_emp_seed = float(hash("fpv_overlay") & 0xFFFF)
	_resolve_siblings()
	var _discard := Events.hull_changed.connect(_on_hull_changed)
	_discard = Events.drone_respawned.connect(_on_drone_respawned)
	_discard = Graphics.graphics_settings_updated.connect(_on_graphics_settings_updated)
	set_full_quality(Graphics.fpv_overlay_full())
	# El casco no emite nada al nacer: sin esto el overlay arrancaría con `damage = 0`
	# aunque el rig se monte sobre un dron ya golpeado (un check, un savegame futuro).
	_pull_damage_from_hull()
	_apply_uniforms()


func _exit_tree() -> void:
	_bind_energy(null)
	if Events.hull_changed.is_connected(_on_hull_changed):
		Events.hull_changed.disconnect(_on_hull_changed)
	if Events.drone_respawned.is_connected(_on_drone_respawned):
		Events.drone_respawned.disconnect(_on_drone_respawned)
	if Graphics.graphics_settings_updated.is_connected(_on_graphics_settings_updated):
		Graphics.graphics_settings_updated.disconnect(_on_graphics_settings_updated)


func _process(delta: float) -> void:
	PerfProbe.begin(&"fpv_overlay")
	tick(delta)
	PerfProbe.end(&"fpv_overlay")


# --- Interfaz pública -------------------------------------------------------------------------

## Fija el daño de la señal, de 0 (enlace limpio) a 1 (casco al borde).
func set_damage(value: float) -> void:
	if not is_finite(value):
		return
	_damage = clampf(value, 0.0, 1.0)
	_apply_uniforms()


## Daño vigente.
func damage() -> float:
	return _damage


## Fija la intensidad del EMP **a mano** y la deja quieta: corta el decaimiento en
## curso. Es la puerta de los checks y de cualquier guion que quiera una pose fija;
## el camino normal es [method trigger_emp].
func set_emp(value: float) -> void:
	if not is_finite(value):
		return
	_emp = clampf(value, 0.0, 1.0)
	_emp_left = 0.0
	_emp_duration = 0.0
	_apply_uniforms()


## Intensidad vigente del EMP, de 1 a 0.
func emp() -> float:
	return _emp


## Arranca un EMP de [param glitch_seconds] segundos: `emp` va de 1 a 0 lineal.
##
## Es lo que se conecta a [signal EnergySystem.emp_hit], y la fórmula es exactamente la
## de [HUDGlitchLayer.trigger_emp] —misma señal, mismo origen, mismo decaimiento—, de
## modo que el glitch del HUD y el de la imagen están **en fase por construcción**
## (`docs/12` §4.3). Un segundo pulso reinicia el contador; no acumula.
func trigger_emp(glitch_seconds: float) -> void:
	if not is_finite(glitch_seconds) or glitch_seconds <= 0.0:
		return
	_emp_duration = glitch_seconds
	_emp_left = glitch_seconds
	_emp = 1.0
	# Cada pulso rompe distinto: si no, dos EMP seguidos desgarran las mismas filas y
	# el segundo se lee como un salto del primero.
	_emp_seed = fmod(_emp_seed + 97.0, 4096.0)
	_apply_uniforms()


## Segundos que le quedan al EMP en curso.
func emp_remaining() -> float:
	return maxf(_emp_left, 0.0)


## Calidad completa (todo el shader) o «solo viñeta» (preset LOW, `docs/13` §3.4).
##
## Cambia el material del rectángulo, no un uniform: el de LOW no declara `screen_tex`,
## así que el renderizador deja de copiar el backbuffer, que es de donde sale el ahorro.
func set_full_quality(full: bool) -> void:
	if _full == full and _rect != null and _rect.material != null:
		return
	_full = full
	if _rect == null:
		return
	_rect.material = _full_material if full else _low_material
	_apply_uniforms()


## `true` si el overlay está en calidad completa.
func is_full_quality() -> bool:
	return _full


## Calidad del enlace de video, de 1 (limpio) a 0 (perdido). Es lo que el `FlightHUD`
## publica en el indicador de SEÑAL (`docs/12`, nota de WP-25).
func signal_quality() -> float:
	return quality_for(_damage, _emp)


## La fórmula de [method signal_quality] sin instancia, para quien tenga los dos
## valores y no el nodo (el HUD, los checks, la parte B de WP-28).
static func quality_for(damage_value: float, emp_value: float) -> float:
	var health := clampf(1.0 - DAMAGE_WEIGHT * clampf(damage_value, 0.0, 1.0), 0.0, 1.0)
	return health * (1.0 - EMP_WEIGHT * clampf(emp_value, 0.0, 1.0))


## El material **vigente** del rectángulo: el completo o el de «solo viñeta».
func material() -> ShaderMaterial:
	return _rect.material as ShaderMaterial if _rect != null else null


## El rectángulo de pantalla completa. Lo mira `overlay_check`.
func rect() -> ColorRect:
	return _rect


## Avanza el reloj del shader y el decaimiento del EMP.
##
## Lo llama [method _process]. Un check que quiera medir en pasos exactos apaga el
## proceso con `set_process(false)` y llama a esto a mano: el overlay no tiene ningún
## otro reloj, así que el resultado es idéntico y reproducible.
func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_time = fmod(_time + delta, TIME_WRAP)
	_update_visibility()
	if _emp_left > 0.0:
		_emp_left = maxf(_emp_left - delta, 0.0)
		_emp = 0.0 if _emp_left <= 0.0 else clampf(_emp_left / maxf(_emp_duration, 0.001),
				0.0, 1.0)
		if _emp_left <= 0.0:
			_emp_duration = 0.0
	_apply_uniforms()


## Reloj interno en segundos. Para los checks y las capturas.
func clock() -> float:
	return _time


## Pone el reloj en [param seconds]. Lo usa `overlay_shots` para capturar siempre la
## misma fase del grano y del latido.
func set_clock(seconds: float) -> void:
	if not is_finite(seconds):
		return
	_time = seconds
	_apply_uniforms()


# --- Construcción -----------------------------------------------------------------------------

## Crea el `ColorRect` de pantalla completa.
##
## En código y no en el `.tscn` por lo mismo que la `FPVCamera` arma su compuesto: el
## rectángulo no tiene nada que un diseñador quiera tocar —anclas 0–1 y nada más— y
## dejarlo acá evita que `drone_rig.tscn` arrastre dos materiales embebidos que solo
## este script sabe llenar.
func _build_rect() -> void:
	_rect = get_node_or_null(^"Rect") as ColorRect
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "Rect"
		add_child(_rect)
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Arma los dos materiales con los valores de `docs/13` §9.
func _build_materials() -> void:
	var full_shader := load(FULL_SHADER) as Shader
	if full_shader == null:
		push_error("FPVOverlay: no se pudo cargar %s (docs/13 §7)." % FULL_SHADER)
		return
	_full_material = ShaderMaterial.new()
	_full_material.shader = full_shader
	_full_material.set_shader_parameter(&"vignette_strength", VIGNETTE_STRENGTH)
	_full_material.set_shader_parameter(&"noise_amount", NOISE_AMOUNT)
	_full_material.set_shader_parameter(&"scanline_amount", SCANLINE_AMOUNT)
	_full_material.set_shader_parameter(&"scanline_count", SCANLINE_COUNT)
	_full_material.set_shader_parameter(&"aberration_px", ABERRATION_PX)
	# El shader no conoce la paleta: el rojo de alarma se lo pasa el script, que sí.
	# Godot convierte el [Color] al `vec3 : source_color` por su cuenta.
	_full_material.set_shader_parameter(&"danger_color", UIPalette.DANGER)

	var low_shader := load(LOW_SHADER) as Shader
	if low_shader == null:
		push_error("FPVOverlay: no se pudo cargar %s (docs/13 §3.4)." % LOW_SHADER)
		return
	_low_material = ShaderMaterial.new()
	_low_material.shader = low_shader
	_low_material.set_shader_parameter(&"vignette_strength", VIGNETTE_STRENGTH)
	if _rect != null:
		_rect.material = _full_material


## Escribe los uniforms que cambian: los dos valores, el reloj y la semilla.
func _apply_uniforms() -> void:
	var active := material()
	if active == null:
		return
	active.set_shader_parameter(&"damage", _damage)
	active.set_shader_parameter(&"time", _time)
	if not _full:
		return
	active.set_shader_parameter(&"emp", _emp)
	active.set_shader_parameter(&"emp_seed", _emp_seed)


## El overlay es la señal **del dron**: si la cámara activa es otra —la cinemática de
## intro, la de reaparición, la de seguimiento— no hay enlace que degradar y el
## rectángulo se esconde, igual que hace el compuesto del ojo de pez.
##
## Si no se pudo resolver la cámara FPV (un rig incompleto, un banco de pruebas) el
## overlay se queda visible: es la opción que no hace desaparecer nada sin avisar.
func _update_visibility() -> void:
	if _rect == null:
		return
	var wanted := true
	if _fpv != null and is_instance_valid(_fpv) and _fpv.is_inside_tree():
		wanted = _fpv.is_current()
	if _rect.visible != wanted:
		_rect.visible = wanted


# --- Fuentes ----------------------------------------------------------------------------------

## Encuentra el [EnergySystem], el [Hull] y la [FPVCamera] del rig.
##
## Por ruta y no por [method DroneRig.get_energy_system]: el `_ready()` de un hijo corre
## **antes** que el del padre, así que al arrancar el rig todavía no resolvió nada. En
## las reapariciones sí se prefiere el accessor, que para entonces ya vale.
func _resolve_siblings() -> void:
	var rig := get_parent()
	if rig == null:
		return
	var drone_rig := rig as DroneRig
	var energy: EnergySystem = drone_rig.get_energy_system() if drone_rig != null else null
	if drone_rig != null and _fpv == null:
		_fpv = drone_rig.get_fpv_camera()
	if energy == null:
		energy = rig.get_node_or_null(^"Drone/EnergySystem") as EnergySystem
	if _fpv == null:
		_fpv = rig.get_node_or_null(^"Drone/CameraRig/FPVCamera") as Camera3D
	_bind_energy(energy)


## El casco del rig, o `null` si el rig no tiene uno.
func _hull() -> Hull:
	var rig := get_parent()
	if rig == null:
		return null
	var drone_rig := rig as DroneRig
	var hull := drone_rig.get_hull() if drone_rig != null else null
	if hull == null:
		hull = rig.get_node_or_null(^"Drone/Hull") as Hull
	return hull


## Lee la integridad del casco y la vuelca en `damage`. Es lo que hace que el overlay
## valga sin esperar a que alguien emita nada.
func _pull_damage_from_hull() -> void:
	var hull := _hull()
	if hull == null:
		return
	set_damage(1.0 - hull.get_ratio())


## Engancha [signal EnergySystem.emp_hit] desconectando primero la del dron anterior.
## Aislado en una función por lo mismo que `CombatHUD._bind_energy_system`: es el único
## punto donde una conexión podría duplicarse al reaparecer.
func _bind_energy(energy: EnergySystem) -> void:
	if _energy != null and is_instance_valid(_energy) \
			and _energy.emp_hit.is_connected(trigger_emp):
		_energy.emp_hit.disconnect(trigger_emp)
	_energy = energy if energy != null and is_instance_valid(energy) else null
	if _energy != null and not _energy.emp_hit.is_connected(trigger_emp):
		var _discard := _energy.emp_hit.connect(trigger_emp)


func _on_hull_changed(ratio: float) -> void:
	set_damage(1.0 - ratio)


## El taller entregó otro dron: la señal vuelve a estar limpia.
##
## `RespawnController._finish()` ya llamó a [method Hull.restore], así que el casco está
## entero y `Events.hull_changed(1.0)` ya pasó; esto se lee igual del [Hull] real en vez
## de dar por sentado el 100 %, porque el que manda es el casco y no el orden de las
## señales. El EMP se corta: el pulso que te tiró era del dron anterior.
func _on_drone_respawned(_score_multiplier: float) -> void:
	_resolve_siblings()
	set_emp(0.0)
	_pull_damage_from_hull()


func _on_graphics_settings_updated() -> void:
	set_full_quality(Graphics.fpv_overlay_full())
