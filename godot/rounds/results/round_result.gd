## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Contabilidad de una partida terminada y su puntaje (`docs/11` §6).
##
## Lo llena [RoundManager] con hechos del bus —nunca los calcula por su cuenta— y lo
## consume [ResultCard]. Es un [RefCounted]: no vive en el árbol y puede sobrevivir al
## nivel que lo produjo.
##
## **Fórmula** (`docs/11` §6.2):
## [codeblock]
## base  = 1000·integridad + 40·partes − 300·muertes + max(0, (par − t)·25)
## score = round(max(0, base) · max(0.3, 0.6^muertes))
## [/codeblock]
##
## El doble castigo por muerte —los −300 y el multiplicador— está **cerrado para el
## MVP** (`docs/11` §12, fila 1): WP-23 lo mide con datos reales y decide.
##
## En derrota el puntaje se calcula y se muestra, pero **no se persiste** (`docs/11` §7).
class_name RoundResult extends RefCounted

## Peso de la integridad de la ciudad en el puntaje base.
const WEIGHT_INTEGRITY: float = 1000.0

## Puntos por parte del enemigo rota.
const WEIGHT_PARTS: float = 40.0

## Castigo por cada reconstrucción del dron.
const PENALTY_DEATH: float = 300.0

## Puntos por segundo por debajo del par de tiempo.
##
## **25 → 8 (WP-23, `docs/11` §12 fila 3).** Con 25 pts/s y un par de 540 s, el bono
## de tiempo valía hasta 13 500 puntos: seis veces el umbral de oro, así que el
## puntaje era el cronómetro y nada más —la integridad de la ciudad, las partes
## rotas y las muertes quedaban en el ruido—. Con 8 pts/s el bono tope baja a
## 4 320 y una victoria de 7–8 min aporta entre 700 y 1 100, que es del orden de
## los 1 000 de la integridad: las cuatro variables vuelven a pesar parecido.
const TIME_BONUS_PER_SECOND: float = 8.0

## Multiplicador por muerte, acumulativo.
const RESPAWN_MULTIPLIER_STEP: float = 0.6

## Piso del multiplicador de respawn (`docs/11` §12, fila 2).
const RESPAWN_MULTIPLIER_FLOOR: float = 0.3

## Cómo terminó el edificio protegido de la ronda (`docs/11` §1).
enum Protected {
	NONE,     ## La ronda no declara edificio protegido.
	STANDING, ## Intacto.
	DAMAGED,  ## Con boquetes, pero en pie.
	FALLEN,   ## Ruina.
}

## Clave de traducción de cada estado, indexada por [enum Protected].
const PROTECTED_KEYS: Array[String] = ["", "RESULT_PROTECTED_STANDING",
		"RESULT_PROTECTED_DAMAGED", "RESULT_PROTECTED_FALLEN"]

## Id de catálogo de la ronda jugada.
var round_id: String = ""

## Verdadero si la ronda terminó en `VICTORY`.
var victory: bool = false

## Segundos acumulados en `BATTLE`, sin pausa y sin cinemática.
var time_seconds: float = 0.0

## Integridad de la ciudad al terminar, de 0.0 a 1.0.
var city_integrity: float = 1.0

## Cómo terminó el edificio protegido, un valor de [enum Protected].
var protected_state: int = Protected.NONE

## Clave de traducción del nombre del edificio protegido, o `""`.
var protected_name_key: String = ""

## Edificios que quedaron en pie al terminar.
var buildings_standing: int = 0

## Edificios que tenía el distrito al empezar (60 en la ronda 1).
var buildings_total: int = 0

## Partes del enemigo rotas, con ids distintos.
var parts_broken: int = 0

## Disparos efectuados (`Events.shot_fired`).
var shots_fired: int = 0

## Impactos confirmados (`Events.hit_confirmed`).
var shots_hit: int = 0

## Veces que el dron fue destruido (`Events.drone_destroyed`).
var deaths: int = 0

## Multiplicador de puntaje por reaparición, tomado de `Events.drone_respawned`
## (`docs/09` §2.8). [method compute_score] lo deduce de [member deaths] si nadie
## lo fijó.
var respawn_multiplier: float = 1.0

## Puntaje antes del multiplicador, ya recortado a cero por abajo.
var base_score: int = 0

## Puntaje final de la partida.
var score: int = 0

## Medalla derivada de [member score] (`RoundCatalog.Medal`).
var medal: int = RoundCatalog.Medal.NONE

## Verdadero si [member score] mejoró el récord guardado. Lo fija la persistencia.
var is_record: bool = false

## Verdadero si [member time_seconds] mejoró el mejor tiempo guardado.
var is_time_record: bool = false


## Precisión de la partida, de 0.0 a 1.0. Sin disparos es 0.
func accuracy() -> float:
	return float(shots_hit) / float(maxi(shots_fired, 1)) if shots_fired > 0 else 0.0


## Estado de [param building] como valor de [enum Protected]. `null` da
## [constant Protected.NONE].
static func state_of_building(building: Building) -> int:
	if building == null or not is_instance_valid(building):
		return Protected.NONE
	match building.stage:
		Building.Stage.RUBBLE:
			return Protected.FALLEN
		Building.Stage.DAMAGED:
			return Protected.DAMAGED
		_:
			return Protected.STANDING


## Multiplicador que corresponde a [param death_count] muertes, con piso
## (`docs/11` §10). `RoundManager` prefiere el que publica `docs/09`, pero si la
## ronda termina entre la destrucción y la reaparición este da el mismo número.
static func multiplier_for(death_count: int) -> float:
	return maxf(RESPAWN_MULTIPLIER_FLOOR, pow(RESPAWN_MULTIPLIER_STEP, float(maxi(death_count, 0))))


## Calcula [member base_score], [member score] y [member respawn_multiplier] contra
## el par de tiempo [param time_par], y devuelve el puntaje final.
func compute_score(time_par: float) -> int:
	respawn_multiplier = minf(respawn_multiplier, multiplier_for(deaths))
	var base := WEIGHT_INTEGRITY * clampf(city_integrity, 0.0, 1.0)
	base += WEIGHT_PARTS * float(parts_broken)
	base -= PENALTY_DEATH * float(deaths)
	# **El bono de tiempo es sólo de la victoria** (WP-19b). Perder rápido no es
	# jugar bien: una derrota a los 200 s con la ciudad al 34.9 % cobraba
	# `(540 − 200) · 8 = 2 720` de bono y salía con 1 221 puntos y medalla de
	# PLATA, premiando exactamente la partida que hay que evitar (medido en
	# WP-23).
	if victory:
		base += maxf(0.0, (time_par - time_seconds) * TIME_BONUS_PER_SECOND)
	base_score = int(roundf(base))
	score = int(roundf(maxf(0.0, base) * respawn_multiplier))
	return score


## Fija y devuelve [member medal] para la ronda [param round_index].
##
## En [b]derrota no hay medalla[/b], por alto que salga el puntaje: la medalla es
## el reconocimiento de una ronda ganada y `docs/11` §7 ya dice que una derrota
## no persiste nada. El puntaje se sigue calculando y mostrando en la tarjeta,
## que es lo que le da al jugador la medida de cuán cerca estuvo.
func resolve_medal(round_index: int) -> int:
	medal = RoundCatalog.Medal.NONE if not victory 			else RoundCatalog.medal_for(round_index, score)
	return medal


## Vuelca el resultado como diccionario plano, para el log y para los checks.
func to_dictionary() -> Dictionary:
	return {
		"round_id": round_id,
		"victory": victory,
		"time_seconds": time_seconds,
		"city_integrity": city_integrity,
		"protected_state": protected_state,
		"protected_name_key": protected_name_key,
		"buildings_standing": buildings_standing,
		"buildings_total": buildings_total,
		"parts_broken": parts_broken,
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"accuracy": accuracy(),
		"deaths": deaths,
		"respawn_multiplier": respawn_multiplier,
		"base_score": base_score,
		"score": score,
		"medal": medal,
		"is_record": is_record,
	}


## Filas de la tarjeta de resultados.
##
## Cada fila trae `label_key` (clave de traducción), `value_text` (ya formateado),
## `highlight` (el valor se dibuja en ámbar) y `header` (la fila es el encabezado de
## un bloque y no lleva valor). La fila del multiplicador sólo aparece cuando hubo
## castigo.
##
## ## Orden nuevo (WP-25b, `docs/narrativa` §8): primero qué quedó en pie
##
## `docs/11` §6.3 abría por el tiempo y cerraba con el puntaje. Ahora abre con el
## bloque **«Qué quedó en pie»** —la escuela, los edificios en pie y la integridad— y
## el puntaje con su medalla quedan al final, que los pone [ResultCard]. El motivo es
## la tercera regla de coherencia de `docs/13` §1: la ciudad se muestra antes que el
## puntaje. Ganar no es sacar un número; es que mañana haya algo en pie.
func summary_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{
			"label_key": "RESULT_STANDING_HEADER",
			"value_text": "",
			"highlight": false,
			"header": true,
		},
	]
	if protected_state != Protected.NONE:
		rows.append({
			"label_key": protected_name_key if not protected_name_key.is_empty()
					else "RESULT_STANDING_HEADER",
			# `TranslationServer` y no `tr()`: esto es un [RefCounted], no vive en el
			# árbol y no tiene el `tr()` de [Node].
			"value_text": TranslationServer.translate(PROTECTED_KEYS[protected_state]),
			# El único resaltado del bloque es el que duele: la escuela caída.
			"highlight": protected_state == Protected.FALLEN,
			"header": false,
		})
	rows.append({
		"label_key": "RESULT_STANDING_COUNT",
		"value_text": "%d/%d" % [buildings_standing, buildings_total],
		"highlight": false,
		"header": false,
	})
	rows.append({
		"label_key": "RESULT_INTEGRITY",
		"value_text": "%d %%" % int(roundf(clampf(city_integrity, 0.0, 1.0) * 100.0)),
		"highlight": false,
		"header": false,
	})
	for row: Dictionary in [
		{"label_key": "RESULT_TIME", "value_text": format_time(time_seconds),
				"highlight": is_time_record},
		{"label_key": "RESULT_PARTS", "value_text": str(parts_broken), "highlight": false},
		{"label_key": "RESULT_ACCURACY",
				"value_text": "%d %%" % int(roundf(accuracy() * 100.0)), "highlight": false},
		{"label_key": "RESULT_DEATHS", "value_text": str(deaths), "highlight": false},
	]:
		row["header"] = false
		rows.append(row)
	if respawn_multiplier < 1.0:
		rows.append({
			"label_key": "RESULT_MULTIPLIER",
			"value_text": "×%.2f" % respawn_multiplier,
			"highlight": false,
			"header": false,
		})
	return rows


## Formatea [param seconds] como `m:ss`.
static func format_time(seconds: float) -> String:
	var total := int(roundf(maxf(seconds, 0.0)))
	return "%d:%02d" % [total / 60, total % 60]
