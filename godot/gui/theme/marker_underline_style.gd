## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Subraya «de rotulador» de los encabezados de sección (`docs/13` §2, WP-25).
##
## Es la **única** decoración de la identidad nueva y la única imperfección de los
## menús: un trazo de [member thickness] píxeles bajo el texto, con un temblor sembrado,
## un salto donde el marcador se secó y los extremos irregulares. Cuenta «lo propio está
## hecho a mano» sin una sola línea de texto, que es la regla de coherencia del
## checkpoint 3b («lo propio tiene imperfección»).
##
## Es un [StyleBox] con script y no un [Control] aparte para que salga del tema: se
## asigna una vez a las variaciones `HeadingLabel` y `SectionLabel` en
## [ThemeBuilder] y todos los encabezados del juego la heredan sin tocar una escena.
##
## El temblor sale de una [RandomNumberGenerator] con [member noise_seed] fijo, así que
## el trazo es **el mismo** en cada cuadro, en cada corrida y en cada captura: es una
## imperfección de diseño, no ruido animado.
@tool
class_name MarkerUnderlineStyle
extends StyleBox

## Color del trazo.
@export var color: Color = UIPalette.ACCENT_DIM

## Grosor del trazo, en píxeles.
@export var thickness: float = 2.0

## Amplitud del temblor vertical, en píxeles.
@export var jitter: float = 1.1

## Cantidad de tramos en que se parte el trazo. Más tramos, más temblor visible.
@export var segments: int = 16

## Semilla del temblor. Fija a propósito: el trazo no cambia entre cuadros.
@export var noise_seed: int = 20260920

## Separación entre la base del [StyleBox] y el trazo, en píxeles.
@export var bottom_inset: float = 4.0

## Sangría izquierda del trazo, en píxeles.
@export var left_inset: float = 1.0

## Fracción del ancho que el trazo **no** cubre por la derecha: el rotulador no llega
## hasta el final de la palabra.
@export var right_slack: float = 0.12

## Largo máximo del trazo, en píxeles.
##
## Un [Label] de encabezado suele ocupar el ancho entero de su tarjeta aunque su texto
## mida cuatro palabras, y un [StyleBox] no sabe cuánto mide el texto: solo recibe el
## rectángulo del control. Sin este tope, la «subraya» se convertía en una regla que
## cruzaba el panel de lado a lado, que es justo lo contrario de un trazo de rotulador.
@export var max_length: float = 180.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if color.a <= 0.0 or thickness <= 0.0 or segments < 2:
		return
	var usable := rect.size.x - left_inset
	if usable <= 4.0:
		return
	var span := minf(usable * (1.0 - clampf(right_slack, 0.0, 0.9)), max_length)
	var base_x := rect.position.x + left_inset
	var base_y := rect.position.y + rect.size.y - bottom_inset
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	# El salto donde el marcador se secó: un tramo interior cualquiera, siempre el mismo.
	var gap_index := 3 + rng.randi() % maxi(segments - 6, 1)
	var previous := Vector2(base_x, base_y + rng.randf_range(-jitter, jitter))
	for index: int in range(1, segments + 1):
		var progress := float(index) / float(segments)
		var point := Vector2(base_x + span * progress,
				base_y + rng.randf_range(-jitter, jitter))
		if index != gap_index:
			# Los extremos adelgazan: el trazo entra y sale sin apoyar del todo.
			var edge := minf(progress, 1.0 - progress) / 0.18
			var width := thickness * clampf(0.45 + 0.55 * edge, 0.35, 1.0)
			RenderingServer.canvas_item_add_line(to_canvas_item, previous, point, color,
					width, true)
		previous = point


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, bottom_inset + thickness)
