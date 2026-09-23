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
## Se dibuja desde el **plano del pueblo** —el `TownPlan` que el distrito publica con
## `get_plan()`—, no desde la geometría. Un pueblo de ruta no tiene carriles: tiene
## manzanas que son polígonos convexos irregulares, una ruta que lo cruza con dos
## quiebres y un círculo de juego. Así que el mapa son tres trazos:
##
## - las **manzanas**, un `draw_colored_polygon` por cada `block_polygon(i)` con su
##   contorno de 1 px; las que están a oscuras (`is_block_dark`) van a menos de la
##   mitad de relleno, lo justo para que el barrio sin luz se note sin volverse un
##   agujero;
## - la **ruta**, la polilínea de `route` con el ancho de `route_width` a escala, que
##   es lo que hace que se lea como una calzada y no como un trazo de dibujo;
## - el **círculo de juego**, punteado, de radio `play_radius` alrededor de
##   `play_centre`. Es el que le dice al jugador dónde termina el pueblo, y sobre él
##   —no contra el borde de la caja— se apoya el chevrón por el que entra el jefe.
##
## La escala es única para los dos ejes, `min(640 / extent.x, 400 / extent.y)` con
## `get_extent()` del plano (2·r·1,35 = 378 m con el radio de 140): son 1,06 px/m y
## el círculo de 148 px entra holgado en la caja de 640 × 400. El norte es **−Z**, así
## que arriba del mapa es el norte y la barra de escala mide los mismos metros en los
## dos ejes por construcción.
##
## La azotea desde la que sale el dron, que puede caer fuera del campo dibujado, se
## recorta contra el borde del mapa en vez de agrandar la ventana del mundo: lo que la
## pantalla cuenta es «salís de acá», no a cuántos metros exactos está.
##
## ## Barrio sin plano
##
## Hoy **no hay ninguno**: el distrito rectangular de P2 ya no existe y todo lo que
## se instancia publica `get_plan()`. La degradación se conserva igual, y no por
## inercia: este componente vive en el `CombatHUD`, que es del nivel de batalla, y el
## nivel de batalla es **uno solo para todas las rondas** (`docs/11` §3). Quién le
## toca de barrio lo decide el catálogo en tiempo de ejecución, así que la pantalla
## no puede dar por sentado que lo que le pongan delante tenga plano.
##
## Con un barrio así la pantalla dibuja el marco, el norte, la escala, el edificio
## protegido, el rombo del dron y el chevrón contra el **borde de la caja**
## (`_border_hit`), y no dibuja manzanas, ruta ni círculo. Sigue contando lo único
## que la alerta tiene que contar: qué hay que defender y por dónde viene el que
## viene. Eso es una pantalla peor, no una pantalla rota, que es exactamente lo que
## se quiere de una degradación.
##
## **Por qué se degradó en vez de conservar el dibujo por carriles**: el dibujo viejo
## dependía de ocho métodos de [CityGrid] que desaparecieron con el pueblo
## —`lane_start`, `lane_width`, `lane_centre`, `lane_count`, `lane_kind`,
## `block_cell`, `block_rows`, `block_cols`—, así que mantenerlo no habría sido
## conservar una degradación sino impedir que el proyecto compilara.
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

## Relleno de una manzana a oscuras (`TownPlan.is_block_dark`): menos de la mitad,
## lo justo para que el barrio sin luz se note sin volverse un agujero.
const BLOCK_DARK_ALPHA: float = 0.035

## Trazo de 1 px de una manzana encendida y de una a oscuras.
const BLOCK_STROKE_ALPHA: float = 0.42
const BLOCK_STROKE_DARK_ALPHA: float = 0.22

## Calzada de la ruta. Va más apagada que el contorno de una manzana porque es una
## banda ancha y no una línea: con el mismo peso se comería el barrio.
const ROUTE_ALPHA: float = 0.26

## Eje de la ruta, el hilo de 1 px por el medio de la calzada. Es lo que la hace
## leer como una ruta y no como una mancha.
const ROUTE_AXIS_ALPHA: float = 0.48

## Círculo de juego.
const RING_ALPHA: float = 0.34

## Segmentos con los que se aproxima el círculo de juego. Con 72 el lado mide 13 px
## en el radio de 148 px de esta ronda: ya no se ve el polígono.
const RING_STEPS: int = 72

## Trazo y hueco del punteado del círculo, en píxeles.
const RING_DASH: float = 6.0
const RING_GAP: float = 6.0

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

## Barrio que se está dibujando. Se guarda como [Node3D] y no como [CityGrid] porque
## lo único que la pantalla le pide es pasar de global a local: todo lo demás sale
## del plano. Así un banco puede atarle un doble sin construir media ciudad.
var _grid: Node3D = null

## Plano del pueblo, o `null` si el distrito no lo publica. Se guarda como [Object] y
## se consulta por `call`/`get`: `TownPlan` es de la ciudad y la pantalla tiene que
## seguir dibujando el distrito que no lo tenga.
var _plan: Object = null

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

## Manzanas, tramos de ruta y círculo que el último `_draw()` dibujó de verdad. Es
## lo que mira `combat_hud_check`: contar lo que se pidió dibujar y no lo que el
## plano dice que hay es lo que hace que la fila signifique algo.
var _blocks_drawn: int = 0
var _route_drawn: int = 0
var _ring_drawn: bool = false


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
	_plan = null
	_protected = null
	refresh()


## Vuelve a leerle a la ronda el barrio, el edificio protegido y los dos extremos de
## la trayectoria. Idempotente y barata: no hace nada si la ronda todavía no tiene
## distrito.
func refresh() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	_protected = _manager.get_protected_building()
	if not bind_district(_manager.get_district()):
		return
	_entry = _grid.to_local(_manager.get_enemy_entry_position())
	_self = _drone_local()
	queue_redraw()


## Ata el mapa al barrio [param district] y devuelve `true` si quedó algo que
## dibujar.
##
## La usa [method refresh] con el distrito de la ronda, y es también la costura por
## la que `combat_hud_check` le pasa el pueblo armado a mano con el que fija el
## dibujo —nueve manzanas y cuatro tramos escritos a mano, a propósito distintos de
## los del pueblo real, así que ningún barrio puede darle la razón por casualidad—.
## Es pública por eso y porque es una operación legítima de la pantalla —«dibujá
## este barrio»— y no un agujero de prueba: no cambia nada más que el barrio.
##
## **Todo lo que sale del plano viene en coordenadas locales del distrito**
## —`play_centre`, `route`, `block_polygon()`—, que es la convención acordada para
## `TownPlan` y para `CityGrid.play_centre()`. Acá no hace falta transformar nada:
## [method _map_point] proyecta desde ese mismo espacio local. Quien sí necesita
## global —la cámara de la cinemática, los `ReflectionProbe`— lo pasa con
## `to_global()` por su cuenta.
func bind_district(district: Node3D) -> bool:
	if district == null or not is_instance_valid(district):
		_grid = null
		_plan = null
		_has_map = false
		return false
	_grid = district
	_plan = _plan_of(district)
	_has_map = true
	queue_redraw()
	return true


## El plano del pueblo de [param district], o `null` si el distrito no lo publica.
func _plan_of(district: Node3D) -> Object:
	if not district.has_method(&"get_plan"):
		return null
	return district.call(&"get_plan") as Object


# --- Consultas (`combat_hud_check`) -----------------------------------------------------------

## `true` cuando la pantalla tiene barrio que dibujar.
func has_map() -> bool:
	return _has_map


## Caja del mapa en coordenadas locales del componente.
func map_rect() -> Rect2:
	_layout()
	return _map


## Manzanas que dibujó el último cuadro. Tiene que coincidir con el
## `block_count()` del plano.
func block_count() -> int:
	return _blocks_drawn


## Tramos de ruta que dibujó el último cuadro.
##
## Con los dos quiebres que pide el contrato son tres, y siguen siendo tres aunque
## la ruta salga del campo dibujado: el recorte de [method _clip_to_map] le corta las
## puntas pero no la parte en pedazos, porque la ruta cruza la caja de lado a lado.
## Si alguna vez diera menos, sería que un tramo entero quedó fuera del mapa, y eso
## es justo lo que `combat_hud_check` tiene que poder ver.
func route_segments() -> int:
	return _route_drawn


## `true` si el último cuadro dibujó el círculo de juego.
func ring_drawn() -> bool:
	return _ring_drawn


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
	var extent := _world_extent()
	_scale = minf(MAP_SIZE.x / maxf(extent.x, 1.0), MAP_SIZE.y / maxf(extent.y, 1.0))


## Cuánto mide el barrio, en metros. Manda el plano; si no hay, se le pregunta al
## distrito por `has_method` y, si tampoco, el mapa se dibuja a 1 px/m.
func _world_extent() -> Vector2:
	if _plan != null:
		return _plan.call(&"get_extent") as Vector2
	if _grid != null and is_instance_valid(_grid) and _grid.has_method(&"get_extent"):
		return _grid.call(&"get_extent") as Vector2
	return MAP_SIZE


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
	_route_drawn = 0
	_ring_drawn = false
	HUDDraw.box(self, _map, 1.0, _amber(PANEL_BORDER_ALPHA), _amber(PANEL_FILL_ALPHA))
	if not _has_map:
		return
	_draw_blocks()
	_draw_route()
	_draw_ring()
	_draw_north()
	_draw_scale()
	# Con plano el chevrón se apoya en el círculo de juego, que es el borde real del
	# pueblo; sin plano no hay círculo y se cae al borde de la caja del mapa.
	var entry := _circle_hit(_entry) if _plan != null else _border_hit(_entry)
	var tip: Vector2 = entry["tip"]
	_draw_trajectory(tip)
	_draw_protected()
	_draw_self()
	_draw_enemy(entry)


## Las manzanas del plano, una por una, como los polígonos que son.
func _draw_blocks() -> void:
	if _plan == null:
		return
	for index: int in int(_plan.call(&"block_count")):
		var polygon := _plan.call(&"block_polygon", index) as PackedVector2Array
		if polygon.size() < 3:
			continue
		var points := PackedVector2Array()
		for corner: Vector2 in polygon:
			points.append(_map_point(Vector3(corner.x, 0.0, corner.y)))
		var dark := bool(_plan.call(&"is_block_dark", index))
		draw_colored_polygon(points, _amber(BLOCK_DARK_ALPHA if dark else BLOCK_ALPHA))
		# `draw_polyline` no cierra el contorno solo: hay que repetirle el primer
		# vértice, o la manzana queda con un lado de menos.
		points.append(points[0])
		draw_polyline(points, _amber(BLOCK_STROKE_DARK_ALPHA if dark
				else BLOCK_STROKE_ALPHA), 1.0)
		_blocks_drawn += 1


## La ruta: la calzada a su ancho real y el eje por el medio.
##
## El ancho sale de `route_width` a escala y no de un número de píxeles fijo, así que
## la ruta se lee ancha porque **es** ancha: diez metros contra los ocho de una calle.
##
## Va **recortada a la caja del mapa**, y es la única cosa del mapa que lo necesita:
## la ruta entra y sale del pueblo, así que por contrato es más larga que el campo
## dibujado. Sin recortar, con el pueblo de verdad se salía del marco por los dos
## costados y se metía por debajo del rótulo de la escuela. Las manzanas y el círculo
## caben por construcción —están dentro del radio de juego— y los dos puntos que
## pueden caer fuera ya se recortan aparte.
func _draw_route() -> void:
	if _plan == null:
		return
	var route := _plan.get(&"route") as PackedVector3Array
	if route.size() < 2:
		return
	var points := PackedVector2Array()
	for point: Vector3 in route:
		points.append(_map_point(point))
	var width := maxf(float(_plan.get(&"route_width")) * _scale, 2.0)
	for run: PackedVector2Array in _clip_to_map(points):
		draw_polyline(run, _amber(ROUTE_ALPHA), width)
		draw_polyline(run, _amber(ROUTE_AXIS_ALPHA), 1.0)
		_route_drawn += run.size() - 1


## El círculo de juego: hasta acá llega el pueblo, y de acá para afuera no hay nada
## que defender. Punteado porque no es una pared: es un límite.
func _draw_ring() -> void:
	if _plan == null:
		return
	var radius := float(_plan.get(&"play_radius"))
	if radius <= 0.0:
		return
	var centre_local := _plan.get(&"play_centre") as Vector3
	var points := PackedVector2Array()
	for step: int in RING_STEPS + 1:
		var angle := TAU * float(step) / float(RING_STEPS)
		points.append(_map_point(centre_local
				+ Vector3(cos(angle), 0.0, sin(angle)) * radius))
	HUDDraw.dashed_polyline(self, points, RING_DASH, RING_GAP, 1.0, _amber(RING_ALPHA))
	_ring_drawn = true


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


## Recorta la polilínea [param points] a la caja del mapa y devuelve los tramos que
## sobreviven, cada uno como una polilínea aparte.
##
## Los trozos contiguos se encadenan en una sola polilínea en vez de dibujarse
## segmento por segmento: `draw_polyline` une los vértices de una misma llamada, y
## con una calzada de diez metros de ancho dos llamadas seguidas dejan una muesca en
## el quiebre.
func _clip_to_map(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for index: int in range(1, points.size()):
		var piece := _clip_segment(points[index - 1], points[index])
		if piece.size() < 2:
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector2Array()
			continue
		if run.is_empty():
			run = piece
		elif run[run.size() - 1].is_equal_approx(piece[0]):
			var _appended := run.append(piece[1])
		else:
			if run.size() >= 2:
				runs.append(run)
			run = piece
	if run.size() >= 2:
		runs.append(run)
	return runs


## Recorta el segmento [param from]–[param to] a la caja del mapa por Liang–Barsky y
## devuelve sus dos extremos, o una lista vacía si el segmento queda entero afuera.
##
## Liang–Barsky y no Cohen–Sutherland porque acá no hace falta iterar: se resuelve el
## intervalo de `t` contra las cuatro rectas de la caja y se evalúa una vez.
func _clip_segment(from: Vector2, to: Vector2) -> PackedVector2Array:
	var delta := to - from
	# Para cada borde, `p` es cuánto avanza el segmento hacia afuera y `q` cuánto le
	# sobra al punto de partida por dentro. Orden: izquierda, derecha, arriba, abajo.
	var edge_p := PackedFloat32Array([-delta.x, delta.x, -delta.y, delta.y])
	var edge_q := PackedFloat32Array([
		from.x - _map.position.x, _map.end.x - from.x,
		from.y - _map.position.y, _map.end.y - from.y])
	var enter := 0.0
	var exit := 1.0
	for index: int in 4:
		var p := edge_p[index]
		var q := edge_q[index]
		if is_zero_approx(p):
			# Paralelo a este borde: o está dentro de la franja, o no entra nunca.
			if q < 0.0:
				return PackedVector2Array()
			continue
		var ratio := q / p
		if p < 0.0:
			enter = maxf(enter, ratio)
		else:
			exit = minf(exit, ratio)
		if enter > exit:
			return PackedVector2Array()
	return PackedVector2Array([from + delta * enter, from + delta * exit])


## Recorta un punto dentro del mapa, con sangría. Lo usan los dos extremos que caen
## fuera del barrio.
func _clamp_into_map(point: Vector2) -> Vector2:
	return Vector2(
			clampf(point.x, _map.position.x + CLAMP_INSET, _map.end.x - CLAMP_INSET),
			clampf(point.y, _map.position.y + CLAMP_INSET, _map.end.y - CLAMP_INSET))


## Proyecta [param local] contra el **círculo de juego** y devuelve el mismo
## `{hit, inward, tip}` que [method _border_hit].
##
## El chevrón del jefe va sobre el círculo y no contra la esquina de la caja porque
## lo que la pantalla tiene que decir es por qué punto del pueblo entra, y el pueblo
## termina en el círculo. Como la escala es la misma en los dos ejes, el círculo del
## mundo sigue siendo un círculo en píxeles y alcanza con normalizar el radio.
func _circle_hit(local: Vector3) -> Dictionary:
	var centre_local := _plan.get(&"play_centre") as Vector3
	var centre_px := _map_point(centre_local)
	var radius_px := float(_plan.get(&"play_radius")) * _scale
	var offset := _map_point(local) - centre_px
	if offset.length_squared() < 0.001:
		offset = Vector2(0.0, -1.0)
	var outward := offset.normalized()
	var hit := centre_px + outward * radius_px
	return {"hit": hit, "inward": -outward, "tip": hit - outward * CHEVRON_LENGTH}


## Proyecta [param local] contra el borde del mapa por el rayo que sale del centro, y
## devuelve `{hit, inward, tip}`: el punto del borde, la dirección hacia adentro y la
## punta del chevrón. Es el camino del distrito sin plano.
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
## punto de aparición que declara el plano si la ronda todavía no lo trae.
func _drone_local() -> Vector3:
	if _manager != null and is_instance_valid(_manager):
		var rig := _manager.drone_rig
		if rig != null and is_instance_valid(rig) and rig.is_inside_tree():
			return _grid.to_local(rig.global_position)
	if _plan != null:
		return (_plan.call(&"drone_spawn") as Transform3D).origin
	return Vector3.ZERO
