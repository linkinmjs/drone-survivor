## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Alerta del monitor del taller (`docs/narrativa` §5, `docs/11` §1, `docs/12` §4.2).
##
## No hay cinemática de apertura: hay **un monitor**. Una pantalla vieja del taller,
## ámbar sobre negro, con un mapa del barrio en trazo simple, el edificio a defender
## resaltado y su nombre al lado, la palabra ALERTA en un rincón y, abajo, el enemigo
## que viene escrito como lo escribiría una máquina. Seis segundos, un corte de
## estática y recién entonces la señal del dron.
##
## ## Las dos voces (`docs/narrativa` §7, `docs/13` §2.2)
##
## **Todo lo propio es ámbar y castellano llano**: «ALERTA», «Proteger: Escuela 12»,
## «cualquier botón para continuar». **Lo enemigo es cian y código**: el chevrón por
## donde entra el jefe, la trayectoria prevista y «ENEMIGO: ARACHNODROID», en Chakra
## Petch y mayúsculas. El color es la mitad del mensaje: si la escuela y el coloso
## fueran del mismo color, la pantalla no diría de qué lado está cada uno.
##
## Sin fichas ni biografías. Es un aviso de vigilancia, no un briefing militar.
##
## ## El mapa
##
## Se dibuja desde el **plano de carriles** de [CityGrid], no desde la geometría: una
## manzana es un rectángulo entre `lane_start()` y `lane_start() + lane_width()` de
## sus celdas extremas, y las calles son los huecos que quedan entre manzanas. Las
## avenidas salen más anchas solas —`lane_width` vale 32 m contra los 16 de una
## calle— y además llevan la línea de su cantero, que es lo que las hace legibles como
## avenidas y no como calles gordas.
##
## La escala es única para los dos ejes, `min(640 / extent.x, 400 / extent.z)` con la
## extensión de [method CityGrid.get_extent]: con el distrito de 432 × 272 m son
## 1,47 px/m y el barrio entra casi exacto en la caja. El norte es **−Z**, así que
## arriba del mapa es el norte y la barra de escala mide los mismos metros en los dos
## ejes por construcción.
##
## Los dos puntos que **no** están dentro del barrio —el marcador por el que entra el
## jefe, a 40 m del borde, y la azotea desde la que sale el dron— se proyectan contra
## el borde del mapa en vez de agrandar la ventana del mundo: lo que la pantalla
## cuenta es «por acá entra», no a cuántos metros exactos está.
##
## ## Acumuladores, nunca [Timer] (`docs/00` §6)
##
## El parpadeo es un `fposmod` sobre [member _time], que avanza con el reloj único del
## `CombatHUD`. Y nunca cae a cero: alterna entre opacidad plena y
## [constant DIM_ALPHA], porque una captura tomada en el medio de un parpadeo que
## apaga del todo parece una pantalla rota.
class_name HUDAlertScreen
extends CombatHUDComponent

# --- Claves (`localization/translations.csv`) -------------------------------------------------

## «ALERTA».
const TITLE_KEY: String = "ALERT_TITLE"

## «Proteger: {0}», con el nombre propio del edificio.
const PROTECT_KEY: String = "ALERT_PROTECT"

## «ENEMIGO: {0}», con el código del enemigo en mayúsculas.
const ENEMY_KEY: String = "ALERT_ENEMY"

## Nombre del enemigo de la ronda 1. La pantalla lo escribe en mayúsculas.
const ENEMY_NAME_KEY: String = "ENEMY_ARACHNODROID"

## «cualquier botón para continuar».
const CONTINUE_KEY: String = "ALERT_CONTINUE"

## Rótulo de la barra de escala, con los metros que mide.
const SCALE_KEY: String = "ALERT_SCALE"

## «vos»: el rombo desde el que sale el dron.
const SELF_KEY: String = "ALERT_YOU"

## Prefijo de la clave del tipo de edificio (`BLD_KIND_SCHOOL`…).
const KIND_PREFIX: String = "BLD_KIND_"

## Letra del tick de norte. No se traduce: es N en los dos idiomas del juego.
const NORTH_MARK: String = "N"

# --- Composición ------------------------------------------------------------------------------

## Caja de composición, centrada en el lienzo. Todo se ubica contra ella y no contra
## el borde de la pantalla: así el monitor sigue siendo el mismo bloque a cualquier
## resolución, mientras el fondo negro sí cubre el lienzo entero.
const DESIGN_SIZE: Vector2 = Vector2(1180.0, 620.0)

## Caja del mapa del barrio, en píxeles (`docs/11` §1).
const MAP_SIZE: Vector2 = Vector2(640.0, 400.0)

## Distancia del borde superior de la composición al borde superior del mapa.
const MAP_TOP_OFFSET: float = 132.0

## Desborde del fondo opaco, en píxeles. Cubre de sobra el desplazamiento máximo que
## el EMP le puede escribir a un componente ([constant HUDGlitchLayer.MAX_OFFSET]).
const EDGE_BLEED: float = 12.0

## Cuerpo de «ALERTA».
const TITLE_SIZE: int = 44

## Línea base de «ALERTA» desde el borde superior de la composición.
const TITLE_BASELINE: float = 46.0

## Cuerpo de la línea del enemigo.
const ENEMY_SIZE: int = 24

## Ancho de la caja de texto del enemigo, que se centra sobre el chevrón.
const ENEMY_WIDTH: float = 460.0

## Hueco entre el borde superior del mapa y la línea base del enemigo.
const ENEMY_GAP: float = 16.0

## Caída de la línea del enemigo cuando el jefe entra por el sur.
const ENEMY_DROP: float = 62.0

## Cuerpo del rótulo del edificio protegido.
const PROTECT_SIZE: int = 24

## Cuerpo del tipo de edificio, bajo el rótulo.
const KIND_SIZE: int = 18

## Hueco entre el borde del mapa y el codo de la línea guía.
const LABEL_GAP: float = 16.0

## Tramo horizontal del codo al ancla del rótulo.
const LABEL_ELBOW: float = 18.0

## Cuerpo de `ALERT_CONTINUE`.
const CONTINUE_SIZE: int = 16

## Cuerpo del contador de segundos.
const COUNT_SIZE: int = 16

## Ancho de la caja del pie, alineada a la derecha.
const FOOTER_WIDTH: float = 420.0

## Separación entre las dos líneas del pie.
const FOOTER_GAP: float = 24.0

## Metros que mide la barra de escala. El texto lo pone [constant SCALE_KEY].
const SCALE_METRES: float = 100.0

## Distancia del borde inferior del mapa a la barra de escala.
const SCALE_OFFSET: float = 26.0

## Cuerpo del rótulo de la escala y del tick de norte.
const MARK_SIZE: int = 14

## Sangría del tick de norte dentro del mapa.
const NORTH_INSET: float = 18.0

## Largo del asta del tick de norte.
const NORTH_LENGTH: float = 20.0

## Sangría a la que se recortan los puntos que caen fuera del barrio.
const CLAMP_INSET: float = 12.0

## Lado del rombo del dron, en píxeles.
const SELF_RADIUS: float = 6.0

## Cuerpo del rótulo «vos».
const SELF_SIZE: int = 16

## Largo del chevrón del enemigo, hacia adentro del mapa.
const CHEVRON_LENGTH: float = 16.0

## Media apertura del chevrón.
const CHEVRON_HALF: float = 11.0

## Lado mínimo del rectángulo del edificio protegido, en píxeles: un bloque medio da
## 29 × 16 px y por debajo de esto dejaría de leerse como un edificio.
const PROTECTED_MIN: float = 15.0

## Holgura del marco parpadeante alrededor del edificio protegido.
const PROTECTED_FRAME_GAP: float = 7.0

# --- Ritmo ------------------------------------------------------------------------------------

## Parpadeo de «ALERTA» y del marco del protegido, en Hz (`docs/11` §1).
const BLINK_HZ: float = 1.0

## Fracción del ciclo con la opacidad plena.
const BLINK_DUTY: float = 0.55

## Opacidad del tramo apagado del parpadeo. **No es cero**: una captura tomada en ese
## tramo tiene que seguir mostrando la palabra.
const DIM_ALPHA: float = 0.32

# --- Colores ----------------------------------------------------------------------------------

## Negro del monitor. Es el fondo más oscuro de la paleta, no un negro inventado.
const BACKGROUND: Color = UIPalette.BG_BOTTOM

## Rótulos secundarios del mapa: norte, escala y «vos».
const MARK_COLOR: Color = UIPalette.HUD_DIM

# Opacidades del mapa. Son **opacidades** y no colores porque el único ámbar del
# juego vive en [constant UIPalette.ACCENT]: repetir aquí sus tres canales sería
# abrir una segunda fuente de verdad de color (`docs/13` §2.2).

## Relleno de una manzana encendida.
const BLOCK_ALPHA: float = 0.08

## Relleno de una manzana a oscuras ([method CityGrid.is_block_dark]): menos de la
## mitad, lo justo para que el barrio sin luz se note sin volverse un agujero.
const BLOCK_DARK_ALPHA: float = 0.035

## Trazo de 1 px de una manzana encendida y de una a oscuras.
const BLOCK_STROKE_ALPHA: float = 0.42
const BLOCK_STROKE_DARK_ALPHA: float = 0.22

## Cantero de una avenida.
const AVENUE_ALPHA: float = 0.30

## Marco y relleno de la caja del mapa.
const PANEL_BORDER_ALPHA: float = 0.34
const PANEL_FILL_ALPHA: float = 0.025

## Línea guía del rótulo del protegido.
const GUIDE_ALPHA: float = 0.55

## Trayectoria prevista del jefe.
const TRAJECTORY_ALPHA: float = 0.55

## Pasos de la viñeta.
const VIGNETTE_STEPS: int = 14

## Profundidad de la viñeta, en píxeles.
const VIGNETTE_DEPTH: float = 126.0

## Opacidad del paso más externo de la viñeta.
const VIGNETTE_ALPHA: float = 0.30

var _manager: RoundManager = null
var _grid: CityGrid = null
var _protected: Building = null

## Punto por el que entra el jefe, en el espacio local del distrito.
var _entry: Vector3 = Vector3.ZERO

## Azotea desde la que sale el dron, en el espacio local del distrito.
var _self: Vector3 = Vector3.ZERO

## `true` cuando la rejilla del distrito ya está disponible. Es `false` entre
## [method CombatHUD.bind_round] y el estado `ALERT`, porque el nivel ata el HUD
## **antes** de que [method RoundManager.begin] instancie el barrio.
var _has_map: bool = false

var _time: float = 0.0

## Caja de composición y caja del mapa del último [method _layout].
var _design: Rect2 = Rect2()
var _map: Rect2 = Rect2()

## Escala mundo → mapa, en píxeles por metro.
var _scale: float = 1.0

## Manzanas y avenidas que el último `_draw()` dibujó de verdad. Es lo que mira
## `combat_hud_check`: contar lo que se pidió dibujar y no lo que la rejilla dice
## que hay es lo que hace que la fila signifique algo.
var _blocks_drawn: int = 0
var _avenues_drawn: int = 0


# --- Vínculos ---------------------------------------------------------------------------------

## Ata la pantalla a la ronda. La llama [method CombatHUD.bind_round].
##
## Los datos no se leen acá: cuando el nivel ata el HUD, [method RoundManager.begin]
## todavía no instanció el distrito. Se leen en [method refresh], que el `CombatHUD`
## dispara al entrar en `ALERT`.
func bind_round(manager: RoundManager) -> void:
	_manager = manager if manager != null and is_instance_valid(manager) else null
	_has_map = false
	_grid = null
	_protected = null
	refresh()


## Vuelve a leerle a la ronda el barrio, el edificio protegido y los dos extremos de
## la trayectoria. Idempotente y barata: no hace nada si la ronda todavía no tiene
## distrito.
func refresh() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	_grid = _manager.get_district()
	_protected = _manager.get_protected_building()
	if _grid == null or not is_instance_valid(_grid):
		_has_map = false
		return
	_entry = _grid.to_local(_manager.get_enemy_entry_position())
	_self = _drone_local()
	_has_map = true
	queue_redraw()


# --- Consultas (`combat_hud_check`) -----------------------------------------------------------

## `true` cuando la pantalla tiene barrio que dibujar.
func has_map() -> bool:
	return _has_map


## Caja del mapa en coordenadas locales del componente.
func map_rect() -> Rect2:
	_layout()
	return _map


## Manzanas que dibujó el último cuadro. Tiene que coincidir con
## [method CityGrid.block_count].
func block_count() -> int:
	return _blocks_drawn


## Avenidas que dibujó el último cuadro: una por eje en el distrito A.
func avenue_count() -> int:
	return _avenues_drawn


## Rótulo del edificio protegido, ya traducido y con su nombre propio adentro.
func protected_text() -> String:
	var building_name := ""
	if _protected != null and is_instance_valid(_protected):
		building_name = _protected.display_name()
	if building_name.is_empty():
		building_name = kind_text()
	if building_name.is_empty():
		return ""
	return tr(PROTECT_KEY).format([building_name])


## Tipo del edificio protegido («Escuela»), o vacío si la ronda no declara ninguno.
func kind_text() -> String:
	if _manager == null or not is_instance_valid(_manager):
		return ""
	var kind := String(_manager.get_protected_kind())
	if kind.is_empty():
		return ""
	return tr(KIND_PREFIX + kind.to_upper())


## Línea del enemigo, ya traducida: «ENEMIGO: ARACHNODROID».
func enemy_text() -> String:
	return tr(ENEMY_KEY).format([tr(ENEMY_NAME_KEY).to_upper()])


## Segundos que le quedan a la alerta, redondeados hacia arriba.
func remaining_text() -> String:
	var left := 0.0
	if _manager != null and is_instance_valid(_manager):
		left = _manager.get_alert_remaining()
	return number_text("%d" % [maxi(ceili(left), 0)])


## `true` en el tramo encendido del parpadeo.
func is_blink_lit() -> bool:
	return fposmod(_time * BLINK_HZ, 1.0) < BLINK_DUTY


# --- Reloj ------------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	_time += delta
	if not _has_map:
		refresh()
	queue_redraw()


# --- Dibujo -----------------------------------------------------------------------------------

func _draw() -> void:
	if not begin_draw():
		return
	_layout()
	# El monitor tapa la señal entera: opaco y con desborde, para que un EMP en curso
	# —que a esta altura de la ronda no debería haber, pero el HUD no lo sabe— no
	# alcance a destapar una franja del nivel por el borde.
	draw_rect(Rect2(Vector2(-EDGE_BLEED, -EDGE_BLEED),
			size + Vector2(EDGE_BLEED, EDGE_BLEED) * 2.0), BACKGROUND, true)
	_draw_map()
	_draw_title()
	_draw_footer()
	_draw_vignette()


## Resuelve las dos cajas y la escala del cuadro en curso. Se recalcula siempre
## porque el `Frame` del `CombatHUD` cambia de tamaño con la ventana.
func _layout() -> void:
	var mid := centre()
	_design = Rect2(mid - DESIGN_SIZE * 0.5, DESIGN_SIZE)
	_map = Rect2(Vector2(mid.x - MAP_SIZE.x * 0.5, _design.position.y + MAP_TOP_OFFSET),
			MAP_SIZE)
	var extent := _grid.get_extent() if _has_map else MAP_SIZE
	_scale = minf(MAP_SIZE.x / maxf(extent.x, 1.0), MAP_SIZE.y / maxf(extent.y, 1.0))


func _draw_title() -> void:
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT,
			1.0 if is_blink_lit() else DIM_ALPHA)
	HUDDraw.text(self, HUDDraw.font_display(),
			Vector2(_design.position.x, _design.position.y + TITLE_BASELINE),
			tr(TITLE_KEY), TITLE_SIZE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, colour)


## «Cualquier botón para continuar» y los segundos que quedan, abajo a la derecha.
func _draw_footer() -> void:
	var left := _design.end.x - FOOTER_WIDTH
	HUDDraw.text(self, HUDDraw.font_text(), Vector2(left, _design.end.y - FOOTER_GAP),
			tr(CONTINUE_KEY), CONTINUE_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, FOOTER_WIDTH,
			UIPalette.TEXT_MUTED)
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(left, _design.end.y),
			remaining_text(), COUNT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, FOOTER_WIDTH,
			CombatHUDPalette.TEXT_DIM)


## Viñeta: unos pocos marcos negros encajados, cada vez más transparentes hacia
## adentro. No es radial —son rectángulos— y no hace falta que lo sea: lo único que
## tiene que hacer es que el borde del tubo no compita con el mapa.
func _draw_vignette() -> void:
	var step := VIGNETTE_DEPTH / float(VIGNETTE_STEPS)
	for index: int in VIGNETTE_STEPS:
		var fade := 1.0 - float(index) / float(VIGNETTE_STEPS)
		var rect := Rect2(Vector2(index, index) * step,
				size - Vector2(index, index) * step * 2.0)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		draw_rect(rect, Color(0.0, 0.0, 0.0, VIGNETTE_ALPHA * fade * fade), false, step + 1.0)


# --- Mapa del barrio --------------------------------------------------------------------------

func _draw_map() -> void:
	_blocks_drawn = 0
	_avenues_drawn = 0
	HUDDraw.box(self, _map, 1.0, _amber(PANEL_BORDER_ALPHA), _amber(PANEL_FILL_ALPHA))
	if not _has_map:
		return
	_draw_blocks()
	_draw_avenues()
	_draw_north()
	_draw_scale()
	var entry := _border_hit(_entry)
	var tip: Vector2 = entry["tip"]
	_draw_trajectory(tip)
	_draw_protected()
	_draw_self()
	_draw_enemy(entry)


## Las quince manzanas, una por una, entre los bordes de sus celdas extremas.
func _draw_blocks() -> void:
	var span := maxi(_grid.block_span, 1)
	for block_z: int in _grid.block_rows:
		for block_x: int in _grid.block_cols:
			var first := _grid.block_cell(block_x, block_z, 0, 0)
			var last := _grid.block_cell(block_x, block_z, span - 1, span - 1)
			var near := _map_point(Vector3(_grid.lane_start(0, first.x), 0.0,
					_grid.lane_start(1, first.y)))
			var far := _map_point(Vector3(
					_grid.lane_start(0, last.x) + _grid.lane_width(0, last.x), 0.0,
					_grid.lane_start(1, last.y) + _grid.lane_width(1, last.y)))
			var rect := Rect2(near, far - near).abs()
			var dark := _grid.is_block_dark(Vector2i(block_x, block_z))
			draw_rect(rect, _amber(BLOCK_DARK_ALPHA if dark else BLOCK_ALPHA), true)
			draw_rect(rect, _amber(BLOCK_STROKE_DARK_ALPHA if dark
					else BLOCK_STROKE_ALPHA), false, 1.0)
			_blocks_drawn += 1


## El cantero de cada avenida, de punta a punta del distrito. Las calles no llevan
## nada: ya son el hueco entre dos manzanas.
func _draw_avenues() -> void:
	var half := _grid.get_extent() * 0.5
	for axis: int in 2:
		for lane: int in _grid.lane_count(axis):
			if _grid.lane_kind(axis, lane) != CityGrid.Lane.AVENUE:
				continue
			var along := _grid.lane_centre(axis, lane)
			var from := Vector3(along, 0.0, -half.y) if axis == 0 \
					else Vector3(-half.x, 0.0, along)
			var to := Vector3(along, 0.0, half.y) if axis == 0 \
					else Vector3(half.x, 0.0, along)
			HUDDraw.line(self, _map_point(from), _map_point(to), 1.0, _amber(AVENUE_ALPHA))
			_avenues_drawn += 1


## Tick de norte, arriba a la izquierda del mapa. El norte es **−Z**, que es hacia
## arriba en el mapa por cómo proyecta [method _map_point].
func _draw_north() -> void:
	var top := _map.position + Vector2(NORTH_INSET, NORTH_INSET)
	var foot := top + Vector2(0.0, NORTH_LENGTH)
	HUDDraw.line(self, foot, top, 1.0, MARK_COLOR)
	HUDDraw.line(self, top, top + Vector2(-4.0, 6.0), 1.0, MARK_COLOR)
	HUDDraw.line(self, top, top + Vector2(4.0, 6.0), 1.0, MARK_COLOR)
	HUDDraw.text(self, HUDDraw.font_mono(), foot + Vector2(8.0, 0.0), NORTH_MARK,
			MARK_SIZE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MARK_COLOR)


## Barra de escala, bajo el borde inferior derecho del mapa. Va **afuera** de la caja
## a propósito: adentro competiría con el rombo del dron, que para esta ronda cae
## justo en esa esquina.
func _draw_scale() -> void:
	var length := SCALE_METRES * _scale
	var y := _map.end.y + SCALE_OFFSET
	var right := _map.end.x
	var left := right - length
	HUDDraw.line(self, Vector2(left, y), Vector2(right, y), 1.0, MARK_COLOR)
	HUDDraw.line(self, Vector2(left, y - 4.0), Vector2(left, y + 4.0), 1.0, MARK_COLOR)
	HUDDraw.line(self, Vector2(right, y - 4.0), Vector2(right, y + 4.0), 1.0, MARK_COLOR)
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(left, y - 8.0), tr(SCALE_KEY),
			MARK_SIZE, HORIZONTAL_ALIGNMENT_CENTER, length, MARK_COLOR)


## Trayectoria prevista del jefe: del chevrón al edificio protegido, punteada y cian.
## Es de ellos, así que es cian; y es una previsión, así que es punteada.
func _draw_trajectory(tip: Vector2) -> void:
	if _protected == null or not is_instance_valid(_protected):
		return
	var target := _protected_rect().get_center()
	HUDDraw.dashed_polyline(self, PackedVector2Array([tip, target]), 5.0, 7.0, 1.0,
			CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, TRAJECTORY_ALPHA))


## El edificio a defender: relleno ámbar pleno, marco parpadeante y línea guía hasta
## su nombre propio, que va **afuera** del mapa para no taparle el barrio.
func _draw_protected() -> void:
	if _protected == null or not is_instance_valid(_protected):
		return
	var rect := _protected_rect()
	draw_rect(rect, CombatHUDPalette.ACCENT, true)
	var frame := rect.grow(PROTECTED_FRAME_GAP)
	HUDDraw.box(self, frame, 1.6, CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT,
			1.0 if is_blink_lit() else DIM_ALPHA))

	var guide := CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT, GUIDE_ALPHA)
	var elbow_x := _map.end.x + LABEL_GAP
	var anchor_y := clampf(rect.get_center().y, _map.position.y + 24.0, _map.end.y - 34.0)
	var anchor := Vector2(elbow_x + LABEL_ELBOW, anchor_y)
	HUDDraw.line(self, Vector2(frame.end.x, rect.get_center().y),
			Vector2(elbow_x, rect.get_center().y), 1.0, guide)
	HUDDraw.line(self, Vector2(elbow_x, rect.get_center().y), anchor, 1.0, guide)

	var text_left := anchor.x + 6.0
	var width := maxf(_design.end.x - text_left, 1.0)
	HUDDraw.text(self, HUDDraw.font_text(), Vector2(text_left, anchor_y + 8.0),
			protected_text(), PROTECT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, width,
			CombatHUDPalette.ACCENT)
	var kind := kind_text()
	if not kind.is_empty():
		HUDDraw.text(self, HUDDraw.font_text(), Vector2(text_left, anchor_y + 32.0),
				kind, KIND_SIZE, HORIZONTAL_ALIGNMENT_LEFT, width, UIPalette.TEXT_MUTED)


## Rombo del dron: de dónde sale el que va a volar. Es ámbar porque es nuestro.
func _draw_self() -> void:
	var centre_point := _clamp_into_map(_map_point(_self))
	var points := PackedVector2Array([
		centre_point + Vector2(0.0, -SELF_RADIUS),
		centre_point + Vector2(SELF_RADIUS, 0.0),
		centre_point + Vector2(0.0, SELF_RADIUS),
		centre_point + Vector2(-SELF_RADIUS, 0.0),
	])
	draw_colored_polygon(points, CombatHUDPalette.ACCENT)
	HUDDraw.text(self, HUDDraw.font_text(), centre_point + Vector2(SELF_RADIUS + 6.0, -2.0),
			tr(SELF_KEY), SELF_SIZE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MARK_COLOR)


## Chevrón cian en el borde por donde entra el jefe, con su código al lado.
func _draw_enemy(entry: Dictionary) -> void:
	var hit: Vector2 = entry["hit"]
	var inward: Vector2 = entry["inward"]
	var tip: Vector2 = entry["tip"]
	var colour := CombatHUDPalette.TARGET
	var side := Vector2(-inward.y, inward.x)
	HUDDraw.line(self, tip, hit + side * CHEVRON_HALF, 2.0, colour)
	HUDDraw.line(self, tip, hit - side * CHEVRON_HALF, 2.0, colour)

	var above := hit.y < _map.get_center().y
	var baseline := (_map.position.y - ENEMY_GAP) if above else (_map.end.y + ENEMY_DROP)
	var box_left := clampf(hit.x - ENEMY_WIDTH * 0.5, _design.position.x,
			maxf(_design.end.x - ENEMY_WIDTH, _design.position.x))
	HUDDraw.text(self, HUDDraw.font_display(), Vector2(box_left, baseline), enemy_text(),
			ENEMY_SIZE, HORIZONTAL_ALIGNMENT_CENTER, ENEMY_WIDTH, colour)


# --- Proyección -------------------------------------------------------------------------------

## El ámbar de la paleta con la opacidad [param alpha]. Todo el mapa se dibuja con
## esto: un solo color, nueve pesos.
func _amber(alpha: float) -> Color:
	return CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT, alpha)


## Pasa un punto del espacio local del distrito a píxeles del mapa. El norte (−Z)
## queda arriba, que es lo que el tick de norte promete.
func _map_point(local: Vector3) -> Vector2:
	return _map.get_center() + Vector2(local.x, local.z) * _scale


## Recorta un punto dentro del mapa, con sangría. Lo usan los dos extremos que caen
## fuera del barrio.
func _clamp_into_map(point: Vector2) -> Vector2:
	return Vector2(
			clampf(point.x, _map.position.x + CLAMP_INSET, _map.end.x - CLAMP_INSET),
			clampf(point.y, _map.position.y + CLAMP_INSET, _map.end.y - CLAMP_INSET))


## Proyecta [param local] contra el borde del mapa por el rayo que sale del centro, y
## devuelve `{hit, inward, tip}`: el punto del borde, la dirección hacia adentro y la
## punta del chevrón.
func _border_hit(local: Vector3) -> Dictionary:
	var mid := _map.get_center()
	var offset := _map_point(local) - mid
	if offset.length_squared() < 0.001:
		offset = Vector2(0.0, -1.0)
	var half := _map.size * 0.5
	var to_side := half.x / maxf(absf(offset.x), 0.001)
	var to_cap := half.y / maxf(absf(offset.y), 0.001)
	var travel := minf(to_side, to_cap)
	var hit := mid + offset * travel
	var inward := Vector2(-signf(offset.x), 0.0) if to_side <= to_cap \
			else Vector2(0.0, -signf(offset.y))
	if inward.is_zero_approx():
		inward = Vector2(0.0, 1.0)
	return {"hit": hit, "inward": inward, "tip": hit + inward * CHEVRON_LENGTH}


## Rectángulo del edificio protegido en el mapa, con un lado mínimo para que un
## bloque chico siga viéndose.
func _protected_rect() -> Rect2:
	var local := _grid.to_local(_protected.global_position)
	var basis := _protected.global_transform.basis
	var half := Vector2(_protected.base_size.x, _protected.base_size.z) * 0.5
	# Caja envolvente en XZ: la pieza puede estar girada un cuarto de vuelta según
	# hacia dónde mire su fachada (`docs/10` §4.3).
	var reach := Vector2(
			absf(basis.x.x * half.x) + absf(basis.z.x * half.y),
			absf(basis.x.z * half.x) + absf(basis.z.z * half.y)) * _scale
	reach = reach.max(Vector2(PROTECTED_MIN, PROTECTED_MIN) * 0.5)
	var mid := _map_point(local)
	return Rect2(mid - reach, reach * 2.0)


## Azotea desde la que sale el dron, en el espacio local del distrito. Se prefiere el
## conjunto vivo —que durante la alerta está congelado donde aparece— y se cae al
## punto de aparición que declara la rejilla si la ronda todavía no lo trae.
func _drone_local() -> Vector3:
	if _manager != null and is_instance_valid(_manager):
		var rig := _manager.drone_rig
		if rig != null and is_instance_valid(rig) and rig.is_inside_tree():
			return _grid.to_local(rig.global_position)
	return CityGrid.DRONE_SPAWN
