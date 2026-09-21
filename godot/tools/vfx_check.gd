## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del pool de efectos visuales (`docs/13` §10.2, `vfx_check`).
##
## Corre así:
##
##     godot --headless --path godot res://tools/vfx_check.tscn
##
## Con `-- --negative` el sub-check 11 pide un haz y **no lo suelta**: la corrida
## tiene que salir en **rojo** por la fila «todo vuelve al pool». Es la prueba de
## que el check mide algo.
##
## ## Qué verifica (`docs/13` §10.2)
##
## | # | Fila |
## |---|---|
## | 1 | 200 pedidos en 20 s mezclando los tipos del catálogo |
## | 2 | `active_emitters()` nunca supera el presupuesto, en HIGH, MEDIUM y LOW |
## | 3 | Todo nodo vuelve al pool: hijos y ranuras ocupadas estables |
## | 4 | Sin fugas: `OBJECT_NODE_COUNT` y `OBJECT_ORPHAN_NODE_COUNT` iguales ±0 |
## | 5 | Con el presupuesto lleno, `request()` devuelve `null` y no crea nodos |
## | 6 | Ningún `GPUParticles3D` sigue `emitting` pasada su vida + 0.5 s |
## | 7 | Las telegrafías se sirven **aunque el presupuesto esté lleno** (§11 #12) |
## | 8 | Contrato de `GPUParticles3D` de §4 en las diecisiete escenas |
## | 9 | Tamaños de pool y coste en emisores iguales a la tabla de §4 |
## | 10 | Un id inexistente devuelve `null` sin efectos secundarios |
## | 11 | Prueba negativa: un efecto sin soltar rompe la fila 3 |
## | 12 | El decal del pisotón: sigue, se congela, golpea y deja el cráter 4 s |
## | 13 | El anillo del EMP crece, destella y devuelve su ranura al apagarse |
## | 14 | Un haz retenido 130 s sigue `busy`; `release()` después lo suelta y apaga |
## | 15 | Un [Telegraph] que sale del árbol en pleno windup devuelve su ranura |
## | 16 | Un pedido denegado por presupuesto ajeno no apaga nada |
## | 17 | Fuera del árbol, el pool no escucha más el bus |
##
## ## Cómo se avanza el tiempo
##
## Con `Engine.time_scale`: los efectos envejecen en `_process`, así que acelerar
## el reloj hace que 20 s de simulación quepan en cinco de reloj de pared. El
## timeout de [CheckRunner] mide segundos reales (`ignore_time_scale`), así que no
## se lo lleva por delante.
##
## ## Por qué el pool va con el bus apagado
##
## `listen_to_events = false`: el check quiere controlar **exactamente** cuántos
## pedidos hay y de qué tipo. Con el bus encendido, cualquier autoload que emita
## durante el arranque metería pedidos que el sub-check 1 no contó.
extends CheckRunner

## Pedidos totales del sub-check 1 (`docs/13` §10.2).
const REQUESTS: int = 200

## Segundos simulados que dura la tanda de pedidos.
const BURST_SECONDS: float = 20.0

## Aceleración del reloj durante la tanda.
const TIME_SCALE: float = 4.0

## Segundos simulados de vaciado tras la tanda. El efecto más largo es
## `collapse` (3.0 s de emisión + 4.2 s de cola) y `impact_armor` deja un decal
## de 6 s, así que con ocho sobra.
const DRAIN_SECONDS: float = 9.0

## Margen sobre la vida de la partícula tras el que un `emitting = true` ya es
## una fuga (`docs/13` §10.2 fila 6).
const EMITTING_GRACE: float = 0.5

## Presupuestos esperados por preset (`docs/13` §3.4).
const EXPECTED_BUDGET: Dictionary[int, int] = {
	Graphics.Quality.LOW: 6,
	Graphics.Quality.MEDIUM: 8,
	Graphics.Quality.HIGH: 12,
}

## Mezcla de ids de la tanda: los que el juego pide de verdad, en la proporción
## en la que los pide. Los impactos son lo más frecuente porque el arma tira a
## 8 disparos por segundo; los derrumbes, lo más raro.
const MIX: Array[StringName] = [
	&"impact_armor", &"impact_armor", &"impact_armor", &"impact_armor",
	&"impact_weak", &"impact_weak", &"impact_weak",
	&"impact_city", &"impact_city",
	&"foot_dust", &"foot_dust", &"foot_dust",
	&"part_detach",
	&"collapse",
	&"drone_sparks",
	&"pickup_flash",
	&"damaged_sparks",
	&"stomp_decal",
	&"emp_ring",
	&"guide_line",
	&"parabola",
	&"siege_column",
	&"laser_beam",
	&"siege_beam",
	&"drone_burst",
	&"muzzle_flash",
]

## Ids de vida manual: el pool no los suelta solo, así que el check los devuelve.
const MANUAL_IDS: Array[StringName] = [
	&"laser_beam", &"siege_beam", &"siege_column", &"guide_line", &"parabola",
	&"emp_ring", &"stomp_decal", &"damaged_sparks",
]

## Segundos simulados que el check retiene un efecto de vida manual antes de
## soltarlo. Es el orden de magnitud de una telegrafía (`docs/07` §5).
const MANUAL_HOLD: float = 1.8

@onready var _pool: VFXPool = get_node_or_null(^"VFXPool") as VFXPool

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _held: Array[Dictionary] = []
var _served: int = 0
var _quality_before: int = 0
var _quality_restored: bool = false
var _peak_emitters: int = 0
var _peak_measured: int = 0
var _budget_violations: int = 0
var _measured_violations: int = 0


func _run() -> void:
	if _pool == null:
		fail("el banco no tiene VFXPool")
		return
	_rng.seed = 0x5C0FFEE
	_quality_before = int(Graphics.quality)

	# La fila 17 monta y tira su propio pool, así que va **antes** de la foto de
	# referencia: si no, los 56 nodos que preasigna y libera moverían el conteo.
	await _check_bus_detach()

	# La foto de referencia se toma con el pool ya construido: lo que se vigila
	# es que la **operación** no cree ni deje nodos, no el coste del arranque.
	await wait_frames(2)
	var children_before := _pool.get_child_count()
	var nodes_before := _node_count()
	var orphans_before := _orphan_count()

	await _check_contract()
	await _check_catalogue()
	await _check_stomp_zone()
	await _check_emp_ring()
	await _check_long_hold()
	await _check_denial_is_harmless()
	await _check_telegraph_exit()
	await _check_budget_denial()
	await _check_telegraph_priority()
	await _check_burst()
	await _check_drain(children_before, nodes_before, orphans_before)

	_report()


## Devuelve el preset de gráficos del jugador **pase lo que pase**.
##
## Estaba al final de [method _run], y ahí no corre si el check aborta por
## `--negative`, por un `await` que nunca vuelve o por el timeout del runner: la
## corrida dejaba `Graphics` en LOW o en HIGH según dónde hubiera muerto.
## [method CheckRunner.finish] sí corre siempre.
func finish() -> void:
	if not _quality_restored:
		_quality_restored = true
		Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	super()


# --------------------------------------------------------------------------
# 8 · Contrato de `GPUParticles3D` de `docs/13` §4
# --------------------------------------------------------------------------

func _check_contract() -> void:
	var seen := 0
	var bad_fps := 0
	var bad_order := 0
	var bad_gi := 0
	var bad_interp := 0
	var bad_shadow := 0
	for child: Node in _pool.get_children():
		var effect := child as VFXEffect
		if effect == null:
			continue
		for particles: GPUParticles3D in effect.particle_systems():
			seen += 1
			if particles.fixed_fps != VFXEffect.PARTICLE_FPS:
				bad_fps += 1
			if particles.draw_order != GPUParticles3D.DRAW_ORDER_VIEW_DEPTH:
				bad_order += 1
			if particles.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
				bad_gi += 1
			if not particles.interpolate:
				bad_interp += 1
			if particles.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				bad_shadow += 1
	expect(seen > 0, "8 · no se encontró ningún GPUParticles3D en el pool")
	expect(bad_fps == 0, "8 · fixed_fps != 30 en %d de %d emisores" % [bad_fps, seen])
	expect(bad_order == 0,
			"8 · draw_order != VIEW_DEPTH en %d de %d emisores" % [bad_order, seen])
	expect(bad_gi == 0, "8 · gi_mode != DISABLED en %d de %d emisores" % [bad_gi, seen])
	expect(bad_interp == 0,
			"8 · interpolate apagado en %d de %d emisores" % [bad_interp, seen])
	expect(bad_shadow == 0,
			"8 · cast_shadow encendido en %d de %d emisores" % [bad_shadow, seen])
	print("  contrato §4: %d emisores en %d escenas" % [seen, VFXPool.SPECS.size()])
	await wait_frames(1)


# --------------------------------------------------------------------------
# 9 y 10 · Catálogo e id inexistente
# --------------------------------------------------------------------------

func _check_catalogue() -> void:
	var total_instances := 0
	for id: StringName in _pool.effect_ids():
		var spec: Dictionary = VFXPool.SPECS[id]
		var size := _pool.pool_size(id)
		total_instances += size
		expect(size == int(spec["size"]),
				"9 · pool de '%s': esperado=%d medido=%d" % [id, int(spec["size"]), size])
	expect(_pool.get_child_count() == total_instances,
			"9 · hijos del pool: esperado=%d medido=%d"
			% [total_instances, _pool.get_child_count()])

	var nodes_before := _node_count()
	var ghost := _pool.request(&"no_existe", Transform3D.IDENTITY)
	expect(ghost == null, "10 · un id inexistente devolvió un nodo")
	expect(_node_count() == nodes_before,
			"10 · un id inexistente creó nodos (%d → %d)" % [nodes_before, _node_count()])
	print("  catálogo: %d ids, %d instancias preasignadas"
			% [_pool.effect_ids().size(), total_instances])
	await wait_frames(1)


# --------------------------------------------------------------------------
# 12 · Ciclo completo de la zona del pisotón (`docs/07` §5.4)
# --------------------------------------------------------------------------

## El aviso del pisotón tiene cuatro momentos y los cuatro se pueden medir sin
## imagen: sigue al objetivo, se congela, golpea y deja el cráter.
##
## Se verifica acá y no sólo con capturas porque el cráter es lo que **queda**
## cuando el aviso ya se apagó, y eso depende de que [VFXDecalZone] siga
## contándose como vivo y de que el pool no le recicle la ranura. Una captura
## dice si se ve; esta fila dice si existe.
func _check_stomp_zone() -> void:
	var node := _pool.request(&"stomp_decal", Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var zone := node as VFXDecalZone
	if zone == null:
		fail("12 · el pool no sirvió 'stomp_decal' o no es un VFXDecalZone")
		return
	zone.set_radius(9.0)

	# 1 · Sigue al punto mientras el aviso corre.
	zone.set_ground_point(Vector3(4.0, 0.0, -7.0))
	expect(zone.ground_point().is_equal_approx(Vector3(4.0, 0.0, -7.0)),
			"12 · la zona no siguió al punto: %s" % str(zone.ground_point()))

	# 2 · Congelada, deja de seguir (los últimos 0.25 s del windup).
	zone.freeze()
	zone.set_ground_point(Vector3(40.0, 0.0, 40.0))
	expect(zone.is_frozen(), "12 · freeze() no marcó la zona como congelada")
	expect(zone.ground_point().is_equal_approx(Vector3(4.0, 0.0, -7.0)),
			"12 · la zona congelada igual se movió a %s" % str(zone.ground_point()))

	# 3 · El pie baja: el aviso se apaga y aparece la marca de cráter.
	zone.strike()
	_pool.release_when_done(node)
	await wait_frames(2)
	var crater := zone.get_node_or_null(^"Crater") as Decal
	expect(crater != null and crater.visible,
			"12 · strike() no encendió el Decal del cráter")
	expect(zone.is_playing(), "12 · la zona se dio por terminada con el cráter puesto")
	expect(_pool.busy_count(&"stomp_decal") == 1,
			"12 · el pool soltó la ranura con el cráter todavía en la calle")

	# 4 · El cráter dura sus 4 s y **después** el pool recupera la ranura.
	Engine.time_scale = TIME_SCALE
	var elapsed := 0.0
	var seen_after_two := false
	while elapsed < VFXDecalZone.CRATER_SECONDS + 1.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not seen_after_two and elapsed >= 2.0:
			seen_after_two = true
			expect(zone.is_playing(),
					"12 · el cráter se apagó a los 2 s y tiene que durar %.1f"
					% VFXDecalZone.CRATER_SECONDS)
	Engine.time_scale = 1.0
	await wait_frames(2)
	expect(_pool.busy_count(&"stomp_decal") == 0,
			"12 · la ranura del pisotón no volvió al pool tras el cráter")
	print("  zona del pisotón: sigue → congela → golpea → cráter de %.1f s"
			% VFXDecalZone.CRATER_SECONDS)


# --------------------------------------------------------------------------
# 13 · Ciclo del anillo del EMP (`docs/07` §5.8)
# --------------------------------------------------------------------------

## El anillo crece con su propio [Tween], destella cuando sale el pulso y se
## apaga. Es el mismo patrón que la zona del pisotón —el aviso se convierte en
## secuela y el pool tiene que recuperar la ranura solo—, así que se mide igual.
func _check_emp_ring() -> void:
	var node := _pool.request(&"emp_ring", Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var ring := node as VFXRing
	if ring == null:
		fail("13 · el pool no sirvió 'emp_ring' o no es un VFXRing")
		return
	ring.set_radius(45.0)
	ring.set_ground_point(Vector3(3.0, 0.0, 3.0))
	ring.grow(0.4)
	ring.flash()
	_pool.release_when_done(node)
	await wait_frames(2)
	expect(ring.is_playing(), "13 · el anillo se apagó en el mismo frame del destello")

	Engine.time_scale = TIME_SCALE
	var elapsed := 0.0
	while elapsed < VFXRing.FLASH_SECONDS + 0.8:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	Engine.time_scale = 1.0
	await wait_frames(2)
	expect(_pool.busy_count(&"emp_ring") == 0,
			"13 · la ranura del EMP no volvió al pool tras el destello")
	print("  anillo del EMP: crece → destella %.1f s → vuelve al pool"
			% VFXRing.FLASH_SECONDS)


# --------------------------------------------------------------------------
# 14 · La retención larga no se reclama sola
# --------------------------------------------------------------------------

## `laser_beam`, `siege_beam` y `damaged_sparks` declaran `hold` en su fila de
## `VFXPool.SPECS`: los retiene una **condición de juego** —la ventana activa de
## un ataque, una parte por debajo del 35 %—, no una animación, y una pelea larga
## pasa de sobra los 120 s de la red del pool.
##
## Antes los reclamaba: el haz parpadeaba a mitad del ataque, dejaba de contar en
## `active_emitters()` y el `release()` de la acción caía sobre una ranura ya
## libre y no apagaba nada, así que un jefe muerto con el haz encendido lo dejaba
## emitiendo. Esta fila cubre las dos mitades.
func _check_long_hold() -> void:
	_release_all()
	await wait_frames(1)
	var node := _pool.request(&"laser_beam", _random_xform())
	var beam := node as VFXBeam
	if beam == null:
		fail("14 · el pool no sirvió 'laser_beam'")
		return
	beam.set_endpoints(Vector3.ZERO, Vector3(0.0, 0.0, 30.0))
	var emitters_before := _pool.active_emitters()
	expect(emitters_before >= 1, "14 · el haz encendido no cuenta emisores")

	# 130 s simulados: diez por encima de la red del pool.
	Engine.time_scale = TIME_SCALE
	var elapsed := 0.0
	while elapsed < VFXPool.MAX_HOLD_SECONDS + 10.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	Engine.time_scale = 1.0
	await wait_frames(2)

	expect(_pool.busy_count(&"laser_beam") == 1,
			"14 · el pool reclamó el haz tras %.0f s de retención" % elapsed)
	expect(_pool.active_emitters() >= 1,
			"14 · el haz retenido dejó de contar emisores (%d)" % _pool.active_emitters())
	expect(beam.is_playing(), "14 · el haz retenido se apagó solo")

	_pool.release(node)
	await wait_frames(1)
	expect(_pool.busy_count(&"laser_beam") == 0,
			"14 · release() no soltó la ranura del haz")
	expect(not beam.is_playing(), "14 · release() no apagó el haz")

	# Y la otra mitad: soltar algo que el pool **ya** reclamó tiene que apagarlo
	# igual, que es el caso del jefe que muere con el haz encendido.
	var again := _pool.request(&"laser_beam", _random_xform()) as VFXBeam
	if again != null:
		again.set_endpoints(Vector3.ZERO, Vector3(0.0, 0.0, 20.0))
		_pool.clear()
		expect(not again.is_playing(), "14 · clear() dejó el haz encendido")
		again.set_endpoints(Vector3.ZERO, Vector3(0.0, 0.0, 20.0))
		_pool.release(again)
		expect(not again.is_playing(),
				"14 · release() sobre una ranura ya libre no apagó el haz")
	print("  retención larga: el haz aguanta %.0f s y se suelta a pedido" % elapsed)
	_release_all()
	await wait_frames(1)


# --------------------------------------------------------------------------
# 16 · Denegar no puede apagar nada
# --------------------------------------------------------------------------

## Con el presupuesto lleno por **otros** ids, un pedido que no entra tiene que
## devolver `null` **sin tocar** la instancia que iba a reciclar.
##
## El orden viejo era reciclar y después mirar el presupuesto: se apagaba un
## efecto vivo para no servir ninguno, que es lo peor de los dos mundos. El caso
## se construye con un haz **retenido y apagado** —lo que le pasa a `head_laser`
## entre dos ventanas activas—: su ranura está ocupada pero no cuenta emisores, así
## que reciclarla no libera nada y el pedido no entra. Si el pool reciclara antes
## de comprobar, la acción se quedaría sin su haz a mitad del ataque.
func _check_denial_is_harmless() -> void:
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	await wait_frames(1)
	_release_all()
	await wait_frames(1)

	var beam := _pool.request(&"laser_beam", _random_xform()) as VFXBeam
	expect(beam != null, "16 · el pool no sirvió el haz de partida")
	if beam == null:
		return
	# Recién servido y sin extremos: retenido, visible para el pool, apagado.
	expect(not beam.is_playing(), "16 · el haz recién servido ya cuenta como encendido")
	expect(_pool.active_emitters() == 0,
			"16 · un haz apagado cuenta %d emisores" % _pool.active_emitters())

	var held: Array[Node3D] = []
	for _i: int in 12:
		var filler := _pool.request(&"impact_armor", _random_xform())
		if filler == null:
			break
		held.append(filler)
	expect(_pool.active_emitters() == _pool.budget(),
			"16 · el presupuesto no llegó a llenarse (%d de %d)"
			% [_pool.active_emitters(), _pool.budget()])

	var denied := _pool.request(&"laser_beam", _random_xform())
	var used := _pool.active_emitters()
	expect(denied == null, "16 · se sirvió un haz con el presupuesto lleno")
	expect(_pool.busy_count(&"laser_beam") == 1,
			"16 · la denegación liberó la ranura del haz retenido")
	expect(used <= _pool.budget(),
			"16 · la denegación dejó %d emisores sobre un tope de %d"
			% [used, _pool.budget()])
	# El haz sigue siendo de quien lo pidió: encenderlo después tiene que funcionar.
	# Nota: encenderlo **sube** el conteo por encima del tope, porque un efecto
	# retenido cuesta 0 mientras está apagado y el presupuesto sólo se cobra al
	# pedirlo. Es un cupo de +1 por haz y está anotado en el informe de la tanda.
	beam.set_endpoints(Vector3.ZERO, Vector3(0.0, 0.0, 25.0))
	expect(beam.is_playing(),
			"16 · el haz retenido no sobrevivió a la denegación")
	print("  denegación limpia: %d emisores de %d al denegar, el haz retenido intacto"
			% [used, _pool.budget()])
	_release_all()
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	await wait_frames(1)


# --------------------------------------------------------------------------
# 17 · Fuera del árbol, el pool no escucha el bus
# --------------------------------------------------------------------------

## `Events` es un autoload y sobrevive al nivel. Un pool desconectado del árbol
## pero todavía conectado al bus seguiría sirviendo efectos —y contándolos— desde
## fuera de la escena, y al cargar la ronda siguiente habría dos pools escuchando
## el mismo hecho.
##
## Se hace con un pool **propio** y no con el del banco porque el del banco corre
## con `listen_to_events = false`, que es justo lo que esta fila necesita probar.
func _check_bus_detach() -> void:
	var probe := VFXPool.new()
	probe.name = "BusProbe"
	probe.listen_to_events = true
	probe.track_enemies = false
	add_child(probe)
	await wait_frames(2)

	Events.hit_confirmed.emit(Vector3.ZERO, false, false, &"armor")
	await wait_frames(1)
	expect(probe.busy_count() == 1,
			"17 · el pool conectado no reaccionó al bus (%d ranuras)" % probe.busy_count())

	remove_child(probe)
	await wait_frames(1)
	var busy_before := probe.busy_count()
	Events.hit_confirmed.emit(Vector3(9.0, 0.0, 9.0), true, false, &"weak")
	await wait_frames(1)
	expect(probe.busy_count() == busy_before,
			"17 · el pool fuera del árbol siguió sirviendo efectos (%d → %d)"
			% [busy_before, probe.busy_count()])
	probe.free()
	await wait_frames(2)
	print("  bus: el pool deja de escuchar al salir del árbol")


# --------------------------------------------------------------------------
# 15 · Un aviso que muere en pleno windup devuelve su ranura
# --------------------------------------------------------------------------

## [method Telegraph._shutdown] sólo corre al final del fundido. Un enemigo que
## muere —o un nivel que se descarga— a mitad del windup no llega ahí, y el decal
## del pisotón se quedaba con su ranura hasta la red del pool.
func _check_telegraph_exit() -> void:
	_release_all()
	await wait_frames(1)
	var profile := TelegraphProfile.new()
	profile.spatial_kind = TelegraphProfile.SpatialKind.DECAL_ZONE
	profile.decal_grow_from = 0.25
	profile.decal_radius = 9.0

	var host := Node3D.new()
	host.name = "TelegraphHost"
	add_child(host)
	var telegraph := Telegraph.new()
	telegraph.name = "Telegraph"
	host.add_child(telegraph)
	await wait_frames(1)

	telegraph.set_profile(profile)
	telegraph.set_ground_point(Vector3(5.0, 0.0, 5.0))
	telegraph.begin(&"stomp", 1.1)
	await wait_frames(1)
	expect(_pool.busy_count(&"stomp_decal") == 1,
			"15 · el aviso no tomó su ranura (%d)" % _pool.busy_count(&"stomp_decal"))
	var zone := telegraph.spatial_effect() as VFXDecalZone
	expect(zone != null, "15 · el aviso no sirvió un VFXDecalZone")

	# Se lo lleva el árbol en pleno windup, sin `end()` ni fundido.
	host.free()
	await wait_frames(2)
	expect(_pool.busy_count(&"stomp_decal") == 0,
			"15 · quedaron %d ranuras de aviso tras liberar el Telegraph"
			% _pool.busy_count(&"stomp_decal"))
	if zone != null and is_instance_valid(zone):
		expect(not zone.visible, "15 · el decal del aviso quedó visible")
	print("  aviso: el Telegraph devuelve su ranura al salir del árbol")
	await wait_frames(1)


# --------------------------------------------------------------------------
# 2 y 5 · Presupuesto por preset y denegación
# --------------------------------------------------------------------------

func _check_budget_denial() -> void:
	for preset: int in [Graphics.Quality.LOW, Graphics.Quality.MEDIUM,
			Graphics.Quality.HIGH]:
		Graphics.apply_quality_preset(preset as Graphics.Quality, false)
		await wait_frames(1)
		var budget := _pool.budget()
		expect(budget == int(EXPECTED_BUDGET[preset]),
				"2 · presupuesto del preset %d: esperado=%d medido=%d"
				% [preset, int(EXPECTED_BUDGET[preset]), budget])

		# Se llena a la fuerza con efectos de 1 y 2 emisores hasta que el pool
		# diga que no, y se comprueba que dijo que no por el presupuesto y no por
		# falta de ranuras.
		_release_all()
		await wait_frames(1)
		var nodes_before := _node_count()
		var filled := 0
		for _i: int in 40:
			var id := _fill_id(filled)
			var node := _pool.request(id, _random_xform())
			if node == null:
				break
			_held.append({"node": node, "release_at": -1.0})
			filled += 1
		var used := _pool.active_emitters()
		expect(used <= budget,
				"2 · preset %d: emisores %d > presupuesto %d" % [preset, used, budget])
		expect(used >= budget - 1,
				"5 · preset %d: se denegó con %d de %d emisores usados"
				% [preset, used, budget])
		var denied := _pool.request(&"impact_weak", _random_xform())
		expect(denied == null,
				"5 · preset %d: con el presupuesto lleno request() sirvió un efecto"
				% preset)
		expect(_node_count() == nodes_before,
				"5 · preset %d: la denegación creó nodos (%d → %d)"
				% [preset, nodes_before, _node_count()])
		print("  preset %d: presupuesto %d, %d efectos, %d emisores en uso"
				% [preset, budget, filled, used])
		_release_all()
		await wait_frames(1)


## Id con el que se llena el presupuesto: se alternan 2 y 1 emisores para que el
## tope se alcance exacto en los tres presets (6, 8 y 12).
func _fill_id(index: int) -> StringName:
	if index < 2:
		return &"collapse"
	return &"impact_armor"


# --------------------------------------------------------------------------
# 7 · Las telegrafías no compiten por el presupuesto (`docs/13` §11 #12)
# --------------------------------------------------------------------------

func _check_telegraph_priority() -> void:
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	await wait_frames(1)
	_release_all()
	for _i: int in 40:
		var node := _pool.request(&"impact_armor", _random_xform())
		if node == null:
			break
		_held.append({"node": node, "release_at": -1.0})
	expect(_pool.request(&"impact_weak", _random_xform()) == null,
			"7 · el presupuesto no llegó a llenarse")
	for id: StringName in [&"stomp_decal", &"emp_ring", &"guide_line",
			&"siege_column", &"parabola"]:
		var aviso := _pool.request(id, _random_xform())
		expect(aviso != null,
				"7 · '%s' se denegó con el presupuesto lleno y es telegrafía obligatoria"
				% id)
		if aviso != null:
			_pool.release(aviso)
	print("  telegrafías servidas con el presupuesto lleno: 5 de 5")
	_release_all()
	await wait_frames(1)


# --------------------------------------------------------------------------
# 1 · Tanda de 200 pedidos en 20 s
# --------------------------------------------------------------------------

func _check_burst() -> void:
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	await wait_frames(1)
	var budget := _pool.budget()
	var requests_before := _pool.request_count()
	var denied_before := _pool.denied_count()
	var interval := BURST_SECONDS / float(REQUESTS)
	var elapsed := 0.0
	var next_request := 0.0

	Engine.time_scale = TIME_SCALE
	while elapsed < BURST_SECONDS:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		_sample(budget)
		_expire_held(elapsed)
		while next_request <= elapsed and _served < REQUESTS:
			next_request += interval
			_request_one(elapsed)
	Engine.time_scale = 1.0

	expect(_served == REQUESTS,
			"1 · pedidos emitidos: esperado=%d medido=%d" % [REQUESTS, _served])
	expect(_budget_violations == 0,
			"2 · active_emitters() superó el presupuesto de %d en %d muestras"
			% [budget, _budget_violations])
	expect(_measured_violations == 0,
			"2 · emisores medidos superaron el presupuesto de %d en %d muestras"
			% [budget, _measured_violations])
	var denied := _pool.denied_count() - denied_before
	var asked := _pool.request_count() - requests_before
	print("  tanda: %d pedidos, %d servidos, %d denegados (%.1f %%); pico %d contados / %d medidos (tope %d)"
			% [asked, asked - denied, denied,
			100.0 * float(denied) / maxf(float(asked), 1.0),
			_peak_emitters, _peak_measured, budget])


## Un pedido de la mezcla. Los de vida manual quedan anotados con el instante en
## que hay que soltarlos: el pool no los suelta solo.
func _request_one(now: float) -> void:
	var id := MIX[_rng.randi_range(0, MIX.size() - 1)]
	var node := _pool.request(id, _random_xform())
	_served += 1
	if node == null or not MANUAL_IDS.has(id):
		return
	_held.append({"node": node, "release_at": now + MANUAL_HOLD})


func _sample(budget: int) -> void:
	var counted := _pool.active_emitters()
	var measured := _pool.measured_emitters()
	_peak_emitters = maxi(_peak_emitters, counted)
	_peak_measured = maxi(_peak_measured, measured)
	if counted > budget:
		_budget_violations += 1
	if measured > budget:
		_measured_violations += 1


func _expire_held(now: float) -> void:
	var index := _held.size() - 1
	while index >= 0:
		var entry := _held[index]
		var at := float(entry["release_at"])
		if at >= 0.0 and now >= at:
			var node := entry["node"] as Node3D
			if node != null and is_instance_valid(node):
				_pool.release(node)
			_held.remove_at(index)
		index -= 1


# --------------------------------------------------------------------------
# 3, 4 y 6 · Vaciado, fugas y emisores colgados
# --------------------------------------------------------------------------

func _check_drain(children_before: int, nodes_before: int, orphans_before: int) -> void:
	# Se sueltan los de vida manual que todavía estén retenidos, salvo en la
	# corrida negativa, donde justamente se deja uno colgado.
	for entry: Dictionary in _held:
		var node := entry["node"] as Node3D
		if node != null and is_instance_valid(node) and float(entry["release_at"]) >= 0.0:
			_pool.release(node)
	_held.clear()

	# Prueba negativa (`docs/13` §10.2): se retiene un efecto de vida manual y no
	# se lo suelta nunca. Va acá y no dentro de la tanda porque el LRU recicla la
	# ranura al siguiente pedido del mismo id —el pool de `emp_ring` es de una— y
	# la fuga se curaría sola sin que el check la viera.
	if _args_has("negative"):
		var leak := _pool.request(&"emp_ring", _random_xform())
		print("  NEGATIVO: se retiene '%s' sin soltarlo"
				% ("emp_ring" if leak != null else "nada: el pool lo denegó"))

	Engine.time_scale = TIME_SCALE
	var elapsed := 0.0
	while elapsed < DRAIN_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	Engine.time_scale = 1.0
	await wait_frames(2)

	var busy := _pool.busy_count()
	expect(busy == 0, "3 · quedaron %d ranuras ocupadas tras el vaciado" % busy)
	expect(_pool.active_emitters() == 0,
			"3 · quedaron %d emisores contados tras el vaciado" % _pool.active_emitters())
	expect(_pool.get_child_count() == children_before,
			"3 · hijos del pool: esperado=%d medido=%d"
			% [children_before, _pool.get_child_count()])

	var nodes_after := _node_count()
	var orphans_after := _orphan_count()
	expect(nodes_after == nodes_before,
			"4 · OBJECT_NODE_COUNT: esperado=%d medido=%d" % [nodes_before, nodes_after])
	expect(orphans_after == orphans_before,
			"4 · OBJECT_ORPHAN_NODE_COUNT: esperado=%d medido=%d"
			% [orphans_before, orphans_after])

	var stuck: Array[String] = []
	for child: Node in _pool.get_children():
		var effect := child as VFXEffect
		if effect == null:
			continue
		for particles: GPUParticles3D in effect.particle_systems():
			if particles.emitting:
				stuck.append("%s/%s" % [child.name, particles.name])
	expect(stuck.is_empty(),
			"6 · %d emisores siguen emitiendo pasada su vida + %.1f s: %s"
			% [stuck.size(), EMITTING_GRACE, ", ".join(stuck)])
	print("  vaciado: ranuras %d, hijos %d/%d, nodos %d/%d, huérfanos %d/%d, colgados %d"
			% [busy, _pool.get_child_count(), children_before, nodes_after, nodes_before,
			orphans_after, orphans_before, stuck.size()])


# --------------------------------------------------------------------------
# Ayudas
# --------------------------------------------------------------------------

func _report() -> void:
	print("  resumen: %d pedidos al pool, %d denegados (%.1f %%)"
			% [_pool.request_count(), _pool.denied_count(),
			100.0 * float(_pool.denied_count()) / maxf(float(_pool.request_count()), 1.0)])


func _release_all() -> void:
	for entry: Dictionary in _held:
		var node := entry["node"] as Node3D
		if node != null and is_instance_valid(node):
			_pool.release(node)
	_held.clear()
	_pool.clear()


## Un punto cualquiera del distrito, para que los efectos no se apilen todos en
## el origen y el pico de emisores sea el real.
func _random_xform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(
			_rng.randf_range(-200.0, 200.0),
			_rng.randf_range(0.0, 40.0),
			_rng.randf_range(-130.0, 130.0)))


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _args_has(key: String) -> bool:
	return user_args().has(key)
