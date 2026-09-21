## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Verificación headless del overlay de la señal FPV (`docs/13` §7).
##
## ```
## "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless \
##     --path godot res://tools/overlay_check.tscn
## ```
##
## Ocho filas sobre el [FPVOverlay] de un `drone_rig.tscn` real —el mismo montaje que
## usa `audio_check`— y no sobre un overlay suelto: lo que hay que demostrar no es que
## el shader compile, es que el nodo **se alimenta solo** desde el casco y desde la
## batería del rig y que sigue haciéndolo después de una reaparición.
##
## | # | Verifica |
## |---|---|
## | 1 | El overlay está en la capa −1 con un `ColorRect` de pantalla completa y un `ShaderMaterial` con los uniforms de §7 en sus valores iniciales |
## | 2 | `Events.hull_changed(0.4)` deja `damage()` en 0,6 y el uniform coincide |
## | 3 | `EnergySystem.emp_hit(3.0)` decae 1 → 0,5 → 0 en 3,0 s exactos, y un segundo pulso reinicia |
## | 4 | `signal_quality()` da 1,0 / 0,55 / 0,30 en los tres casos de la fórmula |
## | 5 | `set_full_quality(false)` deja el material sin lectura de pantalla, y el preset LOW lo apaga solo |
## | 6 | Tras `Events.drone_respawned` el daño refleja el casco real y el EMP queda en 0 |
## | 7 | 20 ciclos de daño y EMP no dejan ni un nodo de más |
## | 8 | Prueba negativa: con `--negative` el EMP no decae y la fila 3 falla |
##
## ## El reloj se avanza a mano
##
## [method FPVOverlay.tick] es la única fuente de tiempo del overlay, así que el check
## apaga su `_process` y llama a `tick(1/60)` el número exacto de veces que hace falta.
## Los plazos de la fila 3 se miden en pasos, no en segundos de pared: no hay tolerancia
## por carga de la máquina y el resultado es idéntico en CI y en escritorio.
##
## ## La prueba negativa
##
## Con `-- --negative` el check vuelve a disparar el EMP en **cada** paso, que es lo que
## haría un decaimiento roto: `emp` se queda clavado en 1,0 y la fila 3 falla en sus
## tres plazos. Sirve para demostrar que la fila mide algo y no que cualquier número
## pasa.
extends CheckRunner

## Paso de reloj con el que se avanza el overlay. Es el `physics_ticks_per_second` del
## proyecto, así que 90 pasos son 1,5 s y 180 son 3,0 s **exactos**.
const STEP: float = 1.0 / 60.0

## Segundos del pulso EMP de la fila 3 (`docs/12` §4.3 y `docs/13` §9).
const GLITCH_SECONDS: float = 3.0

## Tolerancia del decaimiento a mitad de camino, la que pide el contrato de WP-28.
const DECAY_TOLERANCE: float = 0.02

## Tolerancia del cero final. No es 0,0 exacto porque 180 sumas de 1/60 no dan 3,0 en
## coma flotante de 32 bits; lo que se exige es que `emp` haya llegado al piso y que un
## paso más lo deje en 0,0 duro.
const ZERO_TOLERANCE: float = 1e-3

## Ciclos de daño y EMP de la fila 7.
const LEAK_CYCLES: int = 20

## Diferencia de nodos admitida en la fila 7: ninguna.
const LEAK_TOLERANCE: int = 0

## Bandera de la prueba negativa.
const NEGATIVE_ARG: String = "negative"

## Uniforms de identidad de `docs/13` §7 con su valor inicial.
const INITIAL_UNIFORMS: Dictionary[String, float] = {
	"vignette_strength": 0.35,
	"noise_amount": 0.035,
	"scanline_amount": 0.06,
	"scanline_count": 540.0,
	"aberration_px": 1.2,
	"damage": 0.0,
	"emp": 0.0,
}

var _rig: DroneRig = null
var _overlay: FPVOverlay = null
var _energy: EnergySystem = null
var _hull: Hull = null
var _negative: bool = false
var _quality_before: int = 0
var _quality_captured: bool = false


func _run() -> void:
	_negative = user_args().has(NEGATIVE_ARG)
	_quality_before = int(Graphics.quality)
	_quality_captured = true
	if _negative:
		print("  MODO NEGATIVO: el EMP se vuelve a disparar en cada paso; la fila 3 debe fallar.")
	await wait_frames(2)

	_rig = get_node_or_null(^"DroneRig") as DroneRig
	if _rig == null:
		fail("la escena del check no trae 'DroneRig'")
		return
	_overlay = _rig.get_overlay()
	if _overlay == null:
		fail("el DroneRig no expone overlay: falta el nodo 'Overlay' (docs/13 §7)")
		return
	_energy = _rig.get_energy_system()
	_hull = _rig.get_hull()
	# El overlay no vuelve a tener otro reloj que el nuestro: los plazos se miden en
	# pasos exactos y no en segundos de pared.
	_overlay.set_process(false)

	_check_structure()
	_check_hull_damage()
	_check_emp_decay()
	_check_signal_quality()
	await _check_quality_switch()
	_check_respawn()
	await _check_leaks()
	await wait_frames(1)


func finish() -> void:
	# El preset se toca en la fila 5; devolverlo es obligación del check aunque falle.
	if _quality_captured and int(Graphics.quality) != _quality_before:
		Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	super.finish()


# --- [1] Estructura y uniforms iniciales -------------------------------------------------------

func _check_structure() -> void:
	expect(_overlay.layer == FPVOverlay.LAYER,
			"el overlay está en la capa %d y no en la %d (docs/12 §1.1)"
			% [_overlay.layer, FPVOverlay.LAYER])
	var rect := _overlay.rect()
	if rect == null:
		fail("el overlay no tiene el ColorRect 'Rect'")
		return
	var full_rect := is_equal_approx(rect.anchor_left, 0.0) \
			and is_equal_approx(rect.anchor_top, 0.0) \
			and is_equal_approx(rect.anchor_right, 1.0) \
			and is_equal_approx(rect.anchor_bottom, 1.0)
	expect(full_rect, "el ColorRect no está anclado 0–1 (%.2f, %.2f, %.2f, %.2f)"
			% [rect.anchor_left, rect.anchor_top, rect.anchor_right, rect.anchor_bottom])
	expect(rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"el ColorRect no tiene mouse_filter IGNORE (%d)" % int(rect.mouse_filter))

	var material := _overlay.material()
	if material == null or material.shader == null:
		fail("el ColorRect no tiene ShaderMaterial con shader")
		return
	expect(material.shader.resource_path == FPVOverlay.FULL_SHADER,
			"el overlay arranca con '%s' y no con el shader completo"
			% material.shader.resource_path)
	expect(_overlay.is_full_quality() == Graphics.fpv_overlay_full(),
			"la calidad del overlay (%s) no sigue a Graphics.fpv_overlay_full() (%s)"
			% [str(_overlay.is_full_quality()), str(Graphics.fpv_overlay_full())])
	expect(_reads_screen(material),
			"el shader completo no declara 'hint_screen_texture': no puede leer la pantalla")

	var line := PackedStringArray()
	for uniform_name: String in INITIAL_UNIFORMS:
		var value: Variant = material.get_shader_parameter(uniform_name)
		if value == null:
			fail("el uniform '%s' de docs/13 §7 no está puesto en el material" % uniform_name)
			continue
		var wanted: float = INITIAL_UNIFORMS[uniform_name]
		expect_near(float(value), wanted, 0.0001,
				"el uniform '%s' no arranca en su valor de docs/13 §9" % uniform_name)
		line.append("%s %.3f" % [uniform_name, float(value)])
	_expect_danger_color(material)
	print("  [1] capa %d, ColorRect full-rect, %s" % [_overlay.layer, ", ".join(line)])


## El tinte de daño tiene que ser el rojo de alarma de la paleta y no un rojo cualquiera
## cableado en el shader: `docs/13` §2.2 tiene **un solo** rojo de alarma.
func _expect_danger_color(material: ShaderMaterial) -> void:
	var raw: Variant = material.get_shader_parameter("danger_color")
	if raw == null:
		fail("el uniform 'danger_color' no está puesto: el shader no conoce DANGER")
		return
	var got := Vector3.ZERO
	if typeof(raw) == TYPE_COLOR:
		var color: Color = raw
		got = Vector3(color.r, color.g, color.b)
	else:
		got = raw as Vector3
	var wanted := Vector3(UIPalette.DANGER.r, UIPalette.DANGER.g, UIPalette.DANGER.b)
	expect(got.distance_to(wanted) < 0.001,
			"danger_color es %s y UIPalette.DANGER es %s" % [str(got), str(wanted)])


# --- [2] Daño desde el casco -------------------------------------------------------------------

func _check_hull_damage() -> void:
	Events.hull_changed.emit(0.4)
	var uniform := _uniform("damage")
	expect_near(_overlay.damage(), 0.6, 0.0001,
			"hull_changed(0.4) no dejó damage() en 0,6")
	expect_near(uniform, 0.6, 0.0001,
			"el uniform 'damage' no siguió a hull_changed(0.4)")
	print("  [2] hull_changed(0.40) -> damage() %.4f, uniform %.4f"
			% [_overlay.damage(), uniform])
	Events.hull_changed.emit(1.0)
	expect_near(_overlay.damage(), 0.0, 0.0001,
			"hull_changed(1.0) no devolvió damage() a 0")


# --- [3] Decaimiento del EMP -------------------------------------------------------------------

## El pulso entra por el [EnergySystem] **real** del rig, no por una llamada directa al
## overlay: lo que se verifica es la conexión de la señal local, que es justamente la
## que `docs/09` §2.9 saca del bus y la que hay que volver a atar tras cada respawn.
func _check_emp_decay() -> void:
	if _energy == null:
		fail("el rig no trae EnergySystem: no hay señal emp_hit que verificar")
		return
	_energy.apply_emp(0.0, GLITCH_SECONDS)
	var at_zero := _overlay.emp()
	expect_near(at_zero, 1.0, 0.0001, "emp_hit(3.0) no dejó emp() en 1,0 al instante")

	_advance(90)
	var at_half := _overlay.emp()
	expect_near(at_half, 0.5, DECAY_TOLERANCE, "a 1,5 s el EMP no está a la mitad")

	# Segundo pulso a mitad de camino: reinicia, no acumula (`docs/12` §4.3).
	_energy.apply_emp(0.0, GLITCH_SECONDS)
	var restarted := _overlay.emp()
	expect_near(restarted, 1.0, 0.0001, "un segundo emp_hit no reinició el EMP a 1,0")
	_advance(90)
	var after_restart := _overlay.emp()
	expect_near(after_restart, 0.5, DECAY_TOLERANCE,
			"tras reiniciar, a 1,5 s el EMP no vuelve a estar a la mitad (¿acumuló?)")

	_advance(90)
	var at_end := _overlay.emp()
	expect(at_end <= ZERO_TOLERANCE,
			"a los 3,0 s el EMP no llegó al piso (%.6f)" % at_end)
	_advance(1)
	var after_end := _overlay.emp()
	expect(after_end == 0.0, "pasados los 3,0 s el EMP no es 0,0 duro (%.8f)" % after_end)
	expect_near(_uniform("emp"), 0.0, 0.0001, "el uniform 'emp' no siguió al decaimiento")
	print("  [3] emp 1,0 -> %.4f a 1,5 s -> reinicio 1,0 -> %.4f a 1,5 s -> %.6f a 3,0 s -> %.1f"
			% [at_half, after_restart, at_end, after_end])


## Avanza el reloj del overlay [param steps] pasos de [constant STEP].
##
## En modo negativo se vuelve a disparar el pulso en cada paso, que es exactamente el
## síntoma de un decaimiento que no decae.
func _advance(steps: int) -> void:
	for _step: int in steps:
		if _negative and _energy != null:
			_energy.apply_emp(0.0, GLITCH_SECONDS)
		_overlay.tick(STEP)


# --- [4] Calidad de señal ----------------------------------------------------------------------

## La fórmula que la parte B de WP-28 publica en el indicador de SEÑAL del `FlightHUD`.
## Se verifica dos veces: sobre la instancia y sobre [method FPVOverlay.quality_for],
## porque la parte B usa la estática y las dos tienen que dar lo mismo.
func _check_signal_quality() -> void:
	_overlay.set_damage(0.0)
	_overlay.set_emp(0.0)
	var clean := _overlay.signal_quality()
	expect_near(clean, 1.0, 0.0001, "sin daño ni EMP la señal no está a 1,0")

	_overlay.set_damage(0.6)
	var damaged := _overlay.signal_quality()
	expect_near(damaged, 0.55, 0.0001, "con daño 0,6 la señal no está a 0,55")

	_overlay.set_damage(0.0)
	_overlay.set_emp(1.0)
	var jammed := _overlay.signal_quality()
	expect_near(jammed, 0.3, 0.0001, "con EMP 1,0 la señal no está a 0,30")

	_overlay.set_damage(0.6)
	var both := _overlay.signal_quality()
	expect_near(both, 0.55 * 0.3, 0.0001, "daño y EMP juntos no multiplican")
	expect_near(FPVOverlay.quality_for(0.6, 1.0), both, 0.0001,
			"quality_for() no da lo mismo que signal_quality()")
	print("  [4] señal: limpia %.4f, daño 0,6 %.4f, EMP 1,0 %.4f, las dos %.4f"
			% [clean, damaged, jammed, both])
	_overlay.set_damage(0.0)
	_overlay.set_emp(0.0)


# --- [5] Calidad completa y «solo viñeta» ------------------------------------------------------

## Lo que separa LOW del resto no es un uniform: es que el material de LOW **no declara**
## `screen_tex`, y por eso el renderizador deja de copiar el backbuffer. Un check que
## mirara un booleano no distinguiría las dos cosas.
func _check_quality_switch() -> void:
	_overlay.set_full_quality(false)
	var low_material := _overlay.material()
	if low_material == null or low_material.shader == null:
		fail("en «solo viñeta» el ColorRect se quedó sin material")
		return
	expect(not _reads_screen(low_material),
			"el material de «solo viñeta» todavía lee la pantalla: sigue copiando el backbuffer")
	expect(low_material.shader.resource_path == FPVOverlay.LOW_SHADER,
			"en «solo viñeta» el shader es '%s'" % low_material.shader.resource_path)
	expect(not _overlay.is_full_quality(), "is_full_quality() sigue en true tras apagarlo")

	_overlay.set_full_quality(true)
	var full_material := _overlay.material()
	expect(full_material != null and _reads_screen(full_material),
			"set_full_quality(true) no devolvió el shader que lee la pantalla")
	expect(_overlay.is_full_quality(), "is_full_quality() sigue en false tras encenderlo")

	# Y ahora sin tocarlo a mano: lo apaga el preset. `apply_quality_preset` con persist
	# escribe en el `.cfg` **aislado** del check y emite `graphics_settings_updated`,
	# que es la señal a la que el overlay está enganchado.
	Graphics.apply_quality_preset(Graphics.Quality.LOW, true)
	await wait_frames(1)
	expect(not Graphics.fpv_overlay_full(),
			"Graphics.fpv_overlay_full() da true en preset LOW (docs/13 §3.4)")
	expect(not _overlay.is_full_quality(),
			"el preset LOW no apagó el overlay por su cuenta")
	var low_by_preset := _overlay.material()
	expect(low_by_preset != null and not _reads_screen(low_by_preset),
			"en preset LOW el material sigue leyendo la pantalla")

	Graphics.apply_quality_preset(Graphics.Quality.HIGH, true)
	await wait_frames(1)
	expect(Graphics.fpv_overlay_full(),
			"Graphics.fpv_overlay_full() da false en preset HIGH (docs/13 §3.4)")
	expect(_overlay.is_full_quality(), "volver a HIGH no devolvió el overlay completo")
	print("  [5] a mano: lee pantalla %s -> %s -> %s; por preset: LOW lee %s, HIGH lee %s"
			% [str(true), str(_reads_screen(low_material)), str(_reads_screen(full_material)),
			str(_reads_screen(low_by_preset)), str(_reads_screen(_overlay.material()))])


## `true` si el shader de [param material] lee la pantalla.
##
## Se mira el **código** y no [method Shader.get_shader_uniform_list]: Godot no lista
## los samplers con `hint_screen_texture` porque los enlaza solo y no son un parámetro
## que nadie pueda escribir. Y el hint es justamente lo que se quiere medir: es él, y no
## el uso de la textura, el que obliga al renderizador a copiar el backbuffer.
func _reads_screen(material: ShaderMaterial) -> bool:
	if material == null or material.shader == null:
		return false
	for raw_line: String in material.shader.code.split("\n"):
		var line := raw_line.strip_edges()
		# Los comentarios no cuentan: el de `fpv_overlay_low.gdshader` explica
		# precisamente por qué **no** lleva el hint, y una búsqueda cruda sobre el
		# código entero lo daría por positivo.
		if line.begins_with("//") or not line.begins_with("uniform"):
			continue
		if line.contains("hint_screen_texture"):
			return true
	return false


# --- [6] Reaparición ---------------------------------------------------------------------------

## Tras `Events.drone_respawned` el overlay no da por sentado el 100 %: relee el [Hull].
## Se prueba en los dos sentidos —con el casco entero y con el casco a 40 %— porque un
## manejador que se limitara a poner `damage = 0` pasaría la mitad del caso.
func _check_respawn() -> void:
	if _hull == null:
		fail("el rig no trae Hull: no se puede verificar la reaparición")
		return
	# a) casco entero: el overlay tiene que limpiarse aunque le hayamos mentido antes.
	_hull.restore()
	_overlay.set_damage(0.8)
	_overlay.set_emp(1.0)
	Events.drone_respawned.emit(0.6)
	var damage_clean := _overlay.damage()
	var emp_clean := _overlay.emp()
	expect_near(damage_clean, 0.0, 0.0001,
			"tras reaparecer con el casco entero el daño no volvió a 0")
	expect(emp_clean == 0.0, "tras reaparecer el EMP no se cortó (%.4f)" % emp_clean)

	# b) casco a 40 %: el overlay tiene que leer el casco **real**, no el 100 %.
	_hull.apply_damage(_hull.hp * 0.6, Vector3.ZERO)
	var ratio := _hull.get_ratio()
	_overlay.set_damage(0.0)
	Events.drone_respawned.emit(0.6)
	var damage_hurt := _overlay.damage()
	expect_near(damage_hurt, 1.0 - ratio, 0.01,
			"tras reaparecer el daño no refleja la integridad real del casco")
	print("  [6] respawn: casco 1,00 -> damage %.4f, emp %.1f; casco %.2f -> damage %.4f"
			% [damage_clean, emp_clean, ratio, damage_hurt])
	_hull.restore()
	_overlay.set_emp(0.0)


# --- [7] Fugas ---------------------------------------------------------------------------------

func _check_leaks() -> void:
	await wait_frames(3)
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for _cycle: int in LEAK_CYCLES:
		Events.hull_changed.emit(0.25)
		if _energy != null:
			_energy.apply_emp(0.0, GLITCH_SECONDS)
		_advance(30)
		Events.hull_changed.emit(1.0)
		_overlay.set_emp(0.0)
		_overlay.set_full_quality(not _overlay.is_full_quality())
		_overlay.set_full_quality(not _overlay.is_full_quality())
		await get_tree().process_frame
	await wait_frames(3)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("  [7] %d ciclos daño/EMP: %d nodos antes, %d después"
			% [LEAK_CYCLES, before, after])
	expect(absi(after - before) <= LEAK_TOLERANCE,
			"ciclar daño y EMP dejó %d nodos de diferencia (tolerancia %d)"
			% [after - before, LEAK_TOLERANCE])


# --- Utilidades --------------------------------------------------------------------------------

## Valor vigente de un uniform del material activo, o `NAN` si no está puesto.
func _uniform(uniform_name: String) -> float:
	var material := _overlay.material()
	if material == null:
		return NAN
	var value: Variant = material.get_shader_parameter(uniform_name)
	return float(value) if value != null else NAN
