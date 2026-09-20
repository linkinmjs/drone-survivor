## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Catálogo estático de rondas (`docs/11` §2).
##
## No tiene estado de instancia: todo el catálogo es la constante [constant ROUNDS]
## y el resto son funciones puras o derivaciones sobre `GameSettings`. **El id de una
## ronda es para siempre**, porque es la clave con la que se guarda el récord:
## `first-contact` no se renombra nunca, aunque cambien el nombre visible, el distrito
## o el jefe.
##
## Las medallas y los desbloqueos **se derivan**, nunca se guardan (`docs/11` §7): la
## persistencia solo tiene `best_score_<id>` y `best_time_<id>`.
class_name RoundCatalog extends RefCounted

## Medalla derivada del puntaje. Vive acá y no en la persistencia (`docs/11` §2.3).
enum Medal {
	NONE,   ## Por debajo del umbral de bronce, o ronda sin jugar.
	BRONZE, ## Puntaje ≥ `score_bronze`.
	SILVER, ## Puntaje ≥ `score_silver`.
	GOLD,   ## Puntaje ≥ `score_gold`.
}

## Nivel de batalla compartido por todas las rondas (`docs/11` §3). Lo entrega WP-21.
const BATTLE_LEVEL_SCENE: String = "res://rounds/battle_level.tscn"

## Nivel de vuelo libre de WP-11: el terreno de juego del checkpoint 2 y el destino
## provisional de cualquier ronda mientras `battle_level.tscn` no exista.
const FREE_FLIGHT_LEVEL_SCENE: String = "res://rounds/free_flight_level.tscn"

## Menú de rondas (`docs/11` §8). Lo usa la tarjeta de resultado para «Elegir ronda».
const ROUNDS_MENU_SCENE: String = "res://gui/rounds_menu.tscn"

## Cantidad de rondas a partir de la cual el menú deja de mostrar la tarjeta inerte
## de «próximamente» (`docs/11` §2.2).
const FULL_ROSTER: int = 8

## Clave de traducción de cada medalla, indexada por [enum Medal].
const MEDAL_KEYS: Array[String] = ["RESULT_MEDAL_NONE", "RESULT_MEDAL_BRONZE",
		"RESULT_MEDAL_SILVER", "RESULT_MEDAL_GOLD"]

## Rondas del MVP, en orden de progresión (`docs/11` §2.2). El MVP congela una sola.
##
## Campos de cada entrada: `id` (clave de guardado, inmutable), `name_key` y `goal_key`
## (claves de traducción), `district` (escena que se instancia bajo `District`),
## `enemies` (ids de `EnemyCatalog`, en orden de aparición), `time_par` (segundos de
## referencia del bono de tiempo), `score_gold`/`score_silver`/`score_bronze` (umbrales
## inclusivos) y `unlock_after` (id que debe estar completado; `""` = siempre abierta).
const ROUNDS: Array[Dictionary] = [
	{
		"id": "first-contact",
		"name_key": "ROUND_FIRST_CONTACT_NAME",
		"goal_key": "ROUND_FIRST_CONTACT_GOAL",
		"district": "res://city/districts/district_a.tscn",
		"enemies": ["arachnodroid"],
		"time_par": 540.0,
		# **Umbrales recalibrados en WP-23** con los puntajes medidos por
		# `balance_check` sobre tres partidas completas y el bono de tiempo ya
		# bajado a 8 pts/s (`docs/11` §12, fila 3):
		#
		# | Partida medida | integr. | muertes | t | base | ×mult | puntaje |
		# |---|---|---|---|---|---|---|
		# | limpia y rápida (referencia) | 0.70 | 0 | 400 s | 2 220 | 1.00 | **2 220** |
		# | semilla 99 | 0.69 | 1 | 448 s | 1 530 | 0.60 | **918** |
		# | semilla 7 | 0.66 | 2 | 443 s | 1 238 | 0.36 | **446** |
		# | semilla 1 | 0.65 | 2 | 463 s | 1 061 | 0.36 | **382** |
		#
		# Con 600/1300/2000 las tres victorias del bot quedaban **sin medalla**: el
		# castigo por muerte —los −300 y el ×0.6 acumulativo, que `docs/11` §12
		# fila 1 deja cerrados— hunde el puntaje por debajo del bronce con una sola
		# reconstrucción. Bajar plata y bronce mapea la medalla a lo único que
		# distingue de verdad una partida de otra: **cuántas veces te reconstruiste**.
		# Oro queda en 2 000 a propósito, que sólo alcanza una victoria sin muertes
		# y por debajo del par.
		"score_gold": 2000,
		"score_silver": 800,
		"score_bronze": 350,
		"unlock_after": "",
	},
]


## Cantidad de rondas del catálogo.
static func count() -> int:
	return ROUNDS.size()


## Entrada [param index] del catálogo, o un diccionario vacío si el índice no existe.
static func get_round(index: int) -> Dictionary:
	if index < 0 or index >= ROUNDS.size():
		return {}
	return ROUNDS[index]


## Entrada con el id [param id], o un diccionario vacío si no existe.
static func get_by_id(id: String) -> Dictionary:
	var index := get_index(id)
	return {} if index < 0 else ROUNDS[index]


## Índice de la ronda con el id [param id], o `-1` si no existe.
static func get_index(id: String) -> int:
	for index: int in ROUNDS.size():
		if String(ROUNDS[index]["id"]) == id:
			return index
	return -1


## Medalla que corresponde a [param score] en la ronda [param index].
##
## No lee persistencia: recibe el puntaje y devuelve la medalla (`docs/11` §2.3). Un
## índice inválido devuelve [constant Medal.NONE].
static func medal_for(index: int, score: int) -> int:
	var round_data := get_round(index)
	if round_data.is_empty():
		return Medal.NONE
	if score >= int(round_data["score_gold"]):
		return Medal.GOLD
	if score >= int(round_data["score_silver"]):
		return Medal.SILVER
	if score >= int(round_data["score_bronze"]):
		return Medal.BRONZE
	return Medal.NONE


## Medalla ya conseguida en la ronda [param index], derivada del mejor puntaje
## guardado. Una ronda sin récord devuelve [constant Medal.NONE].
static func earned_medal(index: int) -> int:
	var round_data := get_round(index)
	if round_data.is_empty():
		return Medal.NONE
	return medal_for(index, GameSettings.get_best_score(String(round_data["id"])))


## Clave de traducción del nombre de [param medal].
static func medal_key(medal: int) -> String:
	return MEDAL_KEYS[clampi(medal, 0, MEDAL_KEYS.size() - 1)]


## Verdadero si la ronda [param index] está disponible para jugar.
##
## Se deriva, nunca se guarda (`docs/11` §7, `docs/04` §1 nota de WP-03): la primera
## ronda está siempre abierta y las demás se abren cuando la ronda de la que dependen
## tiene récord. Si la entrada declara `unlock_after` manda ese id; si no, manda la
## ronda inmediatamente anterior.
static func is_unlocked(index: int) -> bool:
	var round_data := get_round(index)
	if round_data.is_empty():
		return false
	var required := String(round_data.get("unlock_after", ""))
	if not required.is_empty():
		return GameSettings.has_completed(required)
	if index <= 0:
		return true
	return GameSettings.has_completed(String(ROUNDS[index - 1]["id"]))


## Entradas listas para `ChoiceMenu.setup()` y para `gui/rounds_menu.tscn`.
##
## Cada entrada trae `id`, `index`, `text_key` (la clave del nombre, `docs/11` §2.3),
## `text` (la misma clave: los `Control` traducen solos su `text`), `goal_key`,
## `primary`, `locked`, `medal`, `best_score`, `best_time` y `unlock_after`.
## [param current_id] marca como `primary` a la ronda **siguiente**; si esa está
## bloqueada, el foco cae en la última desbloqueada.
static func menu_entries(current_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index: int in ROUNDS.size():
		var round_data: Dictionary = ROUNDS[index]
		var id := String(round_data["id"])
		entries.append({
			"id": id,
			"index": index,
			"text_key": String(round_data["name_key"]),
			"text": String(round_data["name_key"]),
			"goal_key": String(round_data["goal_key"]),
			"primary": false,
			"locked": not is_unlocked(index),
			"medal": earned_medal(index),
			"best_score": GameSettings.get_best_score(id),
			"best_time": GameSettings.get_best_time(id),
			"unlock_after": String(round_data.get("unlock_after", "")),
		})
	var primary := _primary_index(current_id, entries)
	if primary >= 0:
		entries[primary]["primary"] = true
	return entries


## Escena de nivel que hay que cargar para jugar [param round].
##
## Desde WP-21 siempre es `battle_level.tscn`: hay **un solo** nivel de batalla y lo
## que cambia por ronda es el distrito y los enemigos que instancia [RoundManager]
## (`docs/11` §3). El respaldo al nivel de vuelo libre sólo sobrevive por si alguien
## borra la escena; el parámetro se acepta para no cambiar la firma cuando cada ronda
## elija su nivel.
static func level_scene_for(_round_data: Dictionary) -> String:
	if ResourceLoader.exists(BATTLE_LEVEL_SCENE):
		return BATTLE_LEVEL_SCENE
	return FREE_FLIGHT_LEVEL_SCENE


## Semilla derivada y estable por subsistema (`docs/11` §4.4).
##
## [codeblock]
## derive_seed(tag) == hash(str(Global.round_seed) + ":" + tag)
## [/codeblock]
##
## Que cada subsistema reciba **su** semilla y no un tirón del generador común es lo
## que hace que el orden de las llamadas no altere el resultado: dos ejecuciones con
## la misma [member Global.round_seed] abren igual aunque el jugador no toque nada.
## Etiquetas del MVP: `"personality"`, `"batteries"`, `"debris"`, `"camera"`, `"intro"`.
static func derive_seed(tag: String) -> int:
	return hash("%d:%s" % [Global.round_seed, tag])


## Verdadero mientras el catálogo no llegue a [constant FULL_ROSTER] rondas: el menú
## agrega entonces la tarjeta inerte de «próximamente» (`docs/11` §2.2).
static func shows_coming_soon() -> bool:
	return count() < FULL_ROSTER


## Formatea [param seconds] como `m:ss`. Un valor negativo (sin récord) devuelve `""`.
static func format_time(seconds: float) -> String:
	if seconds < 0.0 or not is_finite(seconds):
		return ""
	var total := int(roundf(seconds))
	return "%d:%02d" % [total / 60, total % 60]


## Índice que recibe `primary`: la ronda siguiente a [param current_id] si está
## desbloqueada, y si no la última desbloqueada del catálogo.
static func _primary_index(current_id: String, entries: Array[Dictionary]) -> int:
	if entries.is_empty():
		return -1
	var wanted := 0
	var current := get_index(current_id)
	if current >= 0:
		wanted = clampi(current + 1, 0, entries.size() - 1)
	if not bool(entries[wanted]["locked"]):
		return wanted
	for index: int in range(entries.size() - 1, -1, -1):
		if not bool(entries[index]["locked"]):
			return index
	return -1
