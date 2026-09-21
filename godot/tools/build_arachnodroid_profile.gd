## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Regenera el balance completo del Arachnodroid desde las tablas de `docs/07`
## §3, §4, §5, §6, §7 y §12:
##
## - `enemies/arachnodroid/attacks/telegraphs/*.tres` — un [TelegraphProfile] por
##   ataque (`docs/06` §3).
## - `enemies/arachnodroid/attacks/*.tres` — los nueve [AttackProfile] de la
##   tabla de `docs/07` §5.1, cada uno con su forma de consulta y su telegrafía.
## - `enemies/arachnodroid/profiles/perception.tres` — el [PerceptionProfile].
## - `enemies/arachnodroid/profiles/arachnodroid_profile.tres` — el
##   [EnemyProfile]: 31 partes, 8 puntos débiles, el rig y las 5 fases.
##
## El balance del jefe son 31 [EnemyPartProfile], 8 [WeakPointProfile], 9 ataques
## y 5 fases: escribirlos a mano en los `.tres` es ilegible y se desincroniza del
## documento al primer ajuste. Acá viven como tablas, en el mismo orden que el
## documento, y los recursos se hornean con `ResourceSaver`. Es el mismo patrón
## de `tools/build_theme.gd`.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_arachnodroid_profile.gd
## [/codeblock]
extends SceneTree

const OUTPUT: String = "res://enemies/arachnodroid/profiles/arachnodroid_profile.tres"

## Perfil de percepción de `docs/07` §12, que esta herramienta también hornea.
## Se guarda antes que el `EnemyProfile` para poder referenciarlo.
const PERCEPTION_OUTPUT: String = "res://enemies/arachnodroid/profiles/perception.tres"

## Carpeta de las fichas de ataque.
const ATTACK_DIR: String = "res://enemies/arachnodroid/attacks"

## Carpeta de las fichas de telegrafía.
const TELEGRAPH_DIR: String = "res://enemies/arachnodroid/attacks/telegraphs"

## Los cuatro lados de pata, en el orden en el que `docs/07` §3 los enumera.
const SIDES: PackedStringArray = ["fl", "fr", "bl", "br"]

## Ids de los cuatro puntos débiles de rodilla; los usan el cono de los núcleos
## y las condiciones de P2, P3 y P4.
const KNEE_IDS: Array = [
	"wp_leg_fl_knee", "wp_leg_fr_knee", "wp_leg_bl_knee", "wp_leg_br_knee",
]

## Ids de los tres núcleos ventrales; son la condición de P5 y la derrota.
const CORE_IDS: Array = ["wp_core_a", "wp_core_b", "wp_core_c"]

## Cian de los anillos de rodilla y del visor: el índice 8 de la paleta del
## `.vox` (55, 170, 248), medido en `docs/05` §13.
const CYAN: Color = Color(0.216, 0.667, 0.973)

## Cian claro de P2 y de la estela del barrido de pata.
const CYAN_BRIGHT: Color = Color(0.60, 0.95, 1.0)

## Magenta ventral: el índice 6 de la paleta (254, 120, 231).
const MAGENTA: Color = Color(0.996, 0.471, 0.906)

## Ámbar de los respiraderos y de los anillos de hombro (`docs/07` §2).
const AMBER: Color = Color(1.0, 0.72, 0.20)

## Rojo de furia de P3 y P4 (`docs/06` §6.1).
const FURY: Color = Color(1.0, 0.25, 0.1)

## Blanco pulsante de la autodestrucción (`docs/07` §6).
const SELFDESTRUCT: Color = Color(1.0, 1.0, 1.0)

## Partes que no son de pata, con los valores de la tabla de `docs/07` §3:
## `[hp, armor, función, desprendible, debris_mass]`. `structure_weight` es 0 en
## todo el blindaje: el jugador no puede ganar disparándole (`docs/07` §3).
const BODY_PARTS: Dictionary = {
	"hull": [6000.0, 0.92, &"core", false, 0.0],
	"neck": [2200.0, 0.90, &"sensor", false, 0.0],
	"antenna_l": [300.0, 0.55, &"cosmetic", true, 250.0],
	"antenna_r": [300.0, 0.55, &"cosmetic", true, 250.0],
	"shoulder_ring": [5000.0, 0.92, &"core", false, 0.0],
	"carapace": [6400.0, 0.90, &"cosmetic", true, 52000.0],
	"underbelly": [4000.0, 0.88, &"core", false, 0.0],
}

## Segmentos de pata, iguales en las cuatro: `[hp, armor, desprendible, masa]`.
const LEG_PARTS: Dictionary = {
	"coxa": [2600.0, 0.92, false, 0.0],
	"femur": [2000.0, 0.88, true, 42000.0],
	"tibia": [1600.0, 0.88, true, 24000.0],
	"foot": [900.0, 0.90, true, 9000.0],
}

## Sesgo ciudad/dron resultante de cada fase (`docs/07` §7, última fila),
## expresado como la fracción que le toca a la ciudad.
##
## `docs/07` lo presenta como una consecuencia de los pesos, no como un campo, y
## `docs/06` no le da uno propio. WP-18 lo necesita explícito para que `approach`
## decida entre la torre y el dron sin sortear nada, así que viaja como un
## multiplicador de fase más —`then.multipliers.city_bias`— y se lee con
## `EnemyBase.phase_multiplier(&"city_bias")`, que ya devuelve 1.0 cuando la fase
## no lo declara.
const CITY_BIAS: Dictionary = {
	"p1_siege": 0.70,
	"p2_alert": 0.50,
	"p3_fury": 0.40,
	"p4_belly": 0.30,
	"p5_selfdestruct": 1.00,
}

## Multiplicadores **acumulados** por fase (`docs/07` §6).
##
## `EnemyBase._enter_phase` **reemplaza** el diccionario de multiplicadores en
## cada cambio de fase, no lo funde. El documento, en cambio, describe efectos
## que se suman: la cadencia ×1.35 de P3 sigue valiendo en P4 y en P5, y el
## `walk_speed ×1.10` de P2 no se pierde al romper la tercera rodilla. Por eso
## cada fila repite lo que arrastra de las anteriores: la tabla es acumulativa
## aunque el mecanismo no lo sea.
##
## **`cooldown` 0.74 → 0.55 desde P3 (WP-23).** Es la palanca que `docs/07` §14
## nombra para las ventanas de daño por minuto: con 0.74 el haz de asedio salía
## 2.3 veces por minuto contra el mínimo de 3 que pide el protocolo, porque su
## ciclo completo —1.8 + 4.0 + 1.5 de ejecución más el enfriamiento— no baja de
## 14.7 s. Con 0.55 el enfriamiento de P3 en adelante cae a 5.5 s y el ciclo a
## 12.8 s, y de paso todo el move set de furia gana la cadencia que el documento
## le promete.
const MULTIPLIERS: Dictionary = {
	"p1_siege": {"city_bias": 0.70},
	"p2_alert": {"walk_speed": 1.10, "city_bias": 0.50},
	"p3_fury": {"walk_speed": 1.10, "cooldown": 0.55, "windup": 0.85, "city_bias": 0.40},
	"p4_belly": {"walk_speed": 1.10, "cooldown": 0.55, "windup": 0.85, "city_bias": 0.30},
	"p5_selfdestruct": {"walk_speed": 1.60, "cooldown": 0.55, "windup": 0.85,
			"city_bias": 1.00},
}

## Pesos de utilidad por fase (`docs/07` §7). `0.0` bloquea la acción.
##
## La fila `walk` del documento la implementa la acción de locomoción
## `approach` (`docs/06` §1, nota de WP-18): las dos claves llevan el mismo
## valor para que la tabla se pueda leer contra el documento sin traducir nada.
const UTILITY: Dictionary = {
	"p1_siege": {
		"walk": 1.00, "approach": 1.00,
		"climb": 1.20, "stomp": 0.70, "leg_sweep": 0.60,
		"head_laser": 0.00, "siege_beam": 1.60, "emp_pulse": 0.00,
		"pounce": 0.00, "shake_off": 0.80,
	},
	"p2_alert": {
		"walk": 1.00, "approach": 1.00,
		"climb": 0.90, "stomp": 1.00, "leg_sweep": 1.00,
		"head_laser": 1.10, "siege_beam": 1.00, "emp_pulse": 0.90,
		"pounce": 0.00, "shake_off": 1.00,
	},
	"p3_fury": {
		"walk": 1.00, "approach": 1.00,
		"climb": 0.60, "stomp": 1.20, "leg_sweep": 1.20,
		"head_laser": 1.30, "siege_beam": 0.60, "emp_pulse": 1.00,
		"pounce": 1.20, "shake_off": 1.20,
	},
	"p4_belly": {
		"walk": 1.00, "approach": 1.00,
		"climb": 0.00, "stomp": 1.40, "leg_sweep": 1.30,
		"head_laser": 1.10, "siege_beam": 0.40, "emp_pulse": 1.00,
		"pounce": 1.50, "shake_off": 1.40,
	},
	"p5_selfdestruct": {
		"walk": 2.00, "approach": 2.00,
		"climb": 0.00, "stomp": 0.00, "leg_sweep": 0.00,
		"head_laser": 0.00, "siege_beam": 0.00, "emp_pulse": 0.00,
		"pounce": 0.00, "shake_off": 1.40,
	},
}

## Los nueve ataques de `docs/07` §5.1, en el mismo orden que los nodos de
## `AttackLibrary` (`docs/06` §3).
##
## `shape` describe la forma de consulta: `["cylinder", radio, altura]`,
## `["box", x, y, z]`, `["capsule", radio, altura]`, `["sphere", radio]` o
## `[]` para las acciones que resuelven por rayo. `telegraph` es la fila del
## [TelegraphProfile] de ese ataque.
const ATTACKS: Array[Dictionary] = [
	{
		# Es la fila `walk` de `docs/07` §5.1 y §7: locomoción con forma de
		# acción, sin telegrafía y sin daño propio (el aplastamiento de 900 por
		# pisada lo cobra el rig, `docs/06` §8.4).
		"id": &"approach", "key": "ATK_WALK",
		"windup": 0.0, "active": 0.6, "recover": 0.0, "cooldown": 0.0,
		"target": AttackProfile.TargetKind.BUILDING,
		"min_range": 0.0, "max_range": 500.0, "lock": false,
		"damage_drone": 0.0, "damage_building": 0.0, "dps": false, "impulse": 0.0,
		"shape": [], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"city_distance", "audio": &"",
		"telegraph": {},
	},
	{
		"id": &"climb", "key": "ATK_CLIMB",
		"windup": 0.6, "active": 3.0, "recover": 0.5, "cooldown": 8.0,
		"target": AttackProfile.TargetKind.BUILDING,
		"min_range": 0.0, "max_range": 120.0, "lock": false,
		"damage_drone": 0.0, "damage_building": 1500.0, "dps": false, "impulse": 0.0,
		"shape": [], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"city_distance", "audio": &"charge_climb",
		"telegraph": {
			"to": AMBER, "kind": TelegraphProfile.SpatialKind.POSTURE, "radius": 0.0,
		},
	},
	{
		"id": &"stomp", "key": "ATK_STOMP",
		"windup": 1.1, "active": 0.25, "recover": 0.8, "cooldown": 6.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 0.0, "max_range": 30.0, "lock": true,
		"damage_drone": 45.0, "damage_building": 2500.0, "dps": false, "impulse": 55.0,
		# **Altura 6 → 12 (WP-23).** `ActionStomp` puntúa contra drones por debajo
		# de `HEIGHT_LIMIT` 12 m, pero el cilindro sólo llegaba a 6: un dron a la
		# altura de las rodillas —6 a 12 m, que es donde `docs/07` §15 #1 lo manda
		# a atacar— provocaba pisotones que no podían tocarlo nunca. Medido antes
		# del cambio: 30 pisotones en 13 min y **cero** impactos al casco. El radio
		# de 9 m, que es lo que dibuja el decal, no se toca.
		"shape": ["cylinder", 9.0, 12.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"distance", "audio": &"charge_stomp",
		"telegraph": {
			# El decal «de 18 m» de `docs/07` §5.4 es el **diámetro** de la zona:
			# 9 m de radio, exactamente el cilindro que resuelve el golpe. Un
			# aviso más grande que el volumen sería mentirle al jugador.
			"to": FURY, "kind": TelegraphProfile.SpatialKind.DECAL_ZONE,
			"radius": 9.0, "grow_from": 0.25,
		},
	},
	{
		"id": &"leg_sweep", "key": "ATK_LEG_SWEEP",
		"windup": 0.9, "active": 0.5, "recover": 1.2, "cooldown": 7.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 0.0, "max_range": 22.0, "lock": true,
		"damage_drone": 60.0, "damage_building": 0.0, "dps": false, "impulse": 40.0,
		"shape": ["box", 14.0, 4.0, 3.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"distance", "audio": &"charge_leg_sweep",
		"telegraph": {
			"to": CYAN_BRIGHT, "kind": TelegraphProfile.SpatialKind.POSTURE,
			"radius": 15.0,
		},
	},
	{
		"id": &"head_laser", "key": "ATK_HEAD_LASER",
		"windup": 1.6, "active": 2.0, "recover": 1.0, "cooldown": 9.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 10.0, "max_range": 90.0, "lock": true,
		"damage_drone": 8.0, "damage_building": 120.0, "dps": true, "impulse": 0.0,
		# **Radio 1.2 → 1.8 (WP-23).** Con 1.2 m el haz no tocó al dron ni una vez
		# en ocho barridos. Es la única acción del jefe que **no** pasa por el gate
		# de apoyo de `docs/06` §10.2, así que desde P3 —con dos patas o menos,
		# cuando `stomp`, `leg_sweep` y `pounce` abortan siempre— es lo único que
		# puede castigar al piloto. 2.5 m es el mismo radio que el haz de asedio y
		# sigue siendo esquivable cortando la LOS o girando más rápido que los
		# 35 °/s del barrido (`docs/07` §5.6). Ajustado después a **1.8**: con 2.5 el
		# haz mataba al dron entre una y cinco veces por partida y `docs/07` §14 pide
		# entre una y tres.
		"shape": ["capsule", 1.8, 90.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"distance", "audio": &"charge_head_laser",
		"telegraph": {
			"to": Color(1.0, 1.0, 1.0), "kind": TelegraphProfile.SpatialKind.GUIDE_LINE,
			"radius": 1.2, "guide_width": 0.25,
		},
	},
	{
		"id": &"siege_beam", "key": "ATK_SIEGE_BEAM",
		"windup": 1.8, "active": 4.0, "recover": 1.5, "cooldown": 10.0,
		"target": AttackProfile.TargetKind.BUILDING,
		"min_range": 0.0, "max_range": 140.0, "lock": true,
		# **700 → 900 /s (WP-23).** Es la palanca de `docs/07` §14 para la ciudad,
		# medida por la partida de control: con 700 /s el jefe sin oposición tardaba
		# **557 s** en bajar la integridad por debajo de 0.35, contra los 240–360 s
		# que piden `docs/07` §14 y `docs/11` §11. El haz está saturado —sale cada
		# 18 s, que es su ciclo mínimo—, así que lo único que queda es el daño por
		# segundo: 1 100 /s son 4 400 por ráfaga, suficiente para llevar una torre de
		# 3 500 HP a ruinas de un solo asedio. Con 900 /s el control todavía tardaba
		# 430 s; con 1 100 cae dentro de la ventana.
		"damage_drone": 0.0, "damage_building": 1100.0, "dps": true, "impulse": 0.0,
		"shape": ["capsule", 2.5, 60.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"time_since_city_attack", "audio": &"charge_siege_beam",
		"telegraph": {
			"to": AMBER, "kind": TelegraphProfile.SpatialKind.COLUMN, "radius": 2.5,
		},
	},
	{
		# Sin daño al casco: el pulso drena la batería (`docs/09` §2.9). Sigue
		# telegrafiando 2.2 s porque `raw_windup()` es lo que manda, no el daño.
		"id": &"emp_pulse", "key": "ATK_EMP_PULSE",
		"windup": 2.2, "active": 0.3, "recover": 1.5, "cooldown": 25.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 0.0, "max_range": 45.0, "lock": true,
		"damage_drone": 0.0, "damage_building": 0.0, "dps": false, "impulse": 0.0,
		"shape": ["sphere", 45.0], "layers": PhysicsLayers.DRONE,
		"score_input": &"distance", "audio": &"charge_emp_pulse",
		"telegraph": {
			# El anillo crece de 0 a 45 m durante el windup: `docs/07` §5.8 lo
			# pide explícito, y es lo que hace el radio legible desde el segundo
			# medio.
			"to": CYAN, "kind": TelegraphProfile.SpatialKind.DECAL_ZONE,
			"radius": 45.0, "grow_from": 0.0,
		},
	},
	{
		"id": &"pounce", "key": "ATK_POUNCE",
		"windup": 1.3, "active": 1.2, "recover": 2.0, "cooldown": 35.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 12.0, "max_range": 55.0, "lock": true,
		"damage_drone": 100.0, "damage_building": 2500.0, "dps": false, "impulse": 0.0,
		"shape": ["sphere", 12.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"distance", "audio": &"charge_pounce",
		"telegraph": {
			"to": FURY, "kind": TelegraphProfile.SpatialKind.PARABOLA,
			"radius": 12.0, "guide_width": 0.35,
		},
	},
	{
		"id": &"shake_off", "key": "ATK_SHAKE_OFF",
		"windup": 0.8, "active": 1.0, "recover": 0.6, "cooldown": 20.0,
		"target": AttackProfile.TargetKind.DRONE,
		"min_range": 0.0, "max_range": 16.0, "lock": true,
		"damage_drone": 25.0, "damage_building": 0.0, "dps": false, "impulse": 80.0,
		"shape": ["sphere", 16.0], "layers": PhysicsLayers.QUERY_SWEEP,
		"score_input": &"distance", "audio": &"charge_shake_off",
		"telegraph": {
			"to": Color(1.0, 1.0, 1.0), "kind": TelegraphProfile.SpatialKind.POSTURE,
			"radius": 16.0,
		},
	},
]

## Ataques que cada fase desbloquea (`docs/07` §6).
const UNLOCKS: Dictionary = {
	"p1_siege": ["walk", "approach", "climb", "stomp", "leg_sweep", "siege_beam",
			"shake_off"],
	"p2_alert": ["head_laser", "emp_pulse"],
	"p3_fury": ["pounce"],
	"p4_belly": [],
	"p5_selfdestruct": [],
}

## Ataques que cada fase bloquea. Los bloqueos **pertenecen a la fase**: al
## entrar en una nueva se limpian y se vuelven a poner (`docs/06` §6.1).
const LOCKS: Dictionary = {
	"p1_siege": [],
	"p2_alert": [],
	"p3_fury": [],
	"p4_belly": ["climb"],
	"p5_selfdestruct": ["climb", "stomp", "leg_sweep", "head_laser", "siege_beam",
			"emp_pulse", "pounce"],
}


func _init() -> void:
	if not _ensure_dir(TELEGRAPH_DIR):
		quit(1)
		return

	var profile := EnemyProfile.new()
	profile.resource_name = "ArachnodroidProfile"
	profile.enemy_id = &"arachnodroid"
	profile.display_key = "ENEMY_ARACHNODROID"
	# `docs/07` §12: los valores del jefe, que son los del framework salvo que se
	# diga lo contrario.
	profile.armor_default = 0.90
	profile.walk_speed = 6.0
	profile.turn_rate = 25.0
	profile.max_step_per_tick = 0.6
	profile.hip_height = 14.0
	profile.stagger_seconds = 0.9
	profile.leg_speed_penalty = 0.15
	profile.downed_legs_lost = 4
	profile.debris_lifetime = 20.0
	profile.detach_speed = 3.0
	profile.personality_spread = 0.30
	profile.decision_hz = 4.0
	profile.top_n = 3
	profile.body_material_emissive = CYAN

	profile.part_overrides = _build_part_overrides()
	profile.weak_points = _build_weak_points()
	profile.leg_rig = _build_leg_rig()
	profile.phases = _build_phases()

	var perception := _build_perception()
	var perception_error := ResourceSaver.save(perception, PERCEPTION_OUTPUT)
	if perception_error != OK:
		push_error("No se pudo guardar %s (error %d)" % [PERCEPTION_OUTPUT, perception_error])
		quit(1)
		return
	profile.perception = ResourceLoader.load(PERCEPTION_OUTPUT, "Resource")

	var attacks := _build_attacks()
	if attacks.is_empty():
		quit(1)
		return
	profile.attacks = attacks

	var err := ResourceSaver.save(profile, OUTPUT)
	if err != OK:
		push_error("No se pudo guardar %s (error %d)" % [OUTPUT, err])
		quit(1)
		return
	print("Perfil guardado en %s (%d partes, %d puntos débiles, %d fases, %d ataques)" \
			% [OUTPUT, profile.part_overrides.size(), profile.weak_points.size(),
			profile.phases.size(), profile.attacks.size()])
	print("Percepción guardada en %s" % PERCEPTION_OUTPUT)
	quit(0)


## Crea [param path] si no existe. Devuelve `false` si no se pudo.
func _ensure_dir(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err == OK or err == ERR_ALREADY_EXISTS:
		return true
	push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
	return false


# --------------------------------------------------------------------------
# Ataques y telegrafías (`docs/07` §5.1 y `docs/06` §3)
# --------------------------------------------------------------------------

## Hornea los nueve [AttackProfile] con su [TelegraphProfile] y los devuelve en
## el orden de [constant ATTACKS].
func _build_attacks() -> Array[AttackProfile]:
	var attacks: Array[AttackProfile] = []
	for row: Dictionary in ATTACKS:
		var attack_id := row["id"] as StringName
		var telegraph_row := row["telegraph"] as Dictionary
		var telegraph: TelegraphProfile = null
		if not telegraph_row.is_empty():
			telegraph = _build_telegraph(attack_id, telegraph_row, row["audio"] as StringName)
			var telegraph_path := "%s/%s.tres" % [TELEGRAPH_DIR, attack_id]
			var telegraph_error := ResourceSaver.save(telegraph, telegraph_path)
			if telegraph_error != OK:
				push_error("No se pudo guardar %s (error %d)"
						% [telegraph_path, telegraph_error])
				return []
			telegraph = ResourceLoader.load(telegraph_path, "Resource") as TelegraphProfile

		var attack := AttackProfile.new()
		attack.resource_name = String(attack_id)
		attack.attack_id = attack_id
		attack.display_key = String(row["key"])
		attack.windup = float(row["windup"])
		attack.active = float(row["active"])
		attack.recover = float(row["recover"])
		attack.cooldown = float(row["cooldown"])
		attack.target_kind = int(row["target"]) as AttackProfile.TargetKind
		attack.min_range = float(row["min_range"])
		attack.max_range = float(row["max_range"])
		attack.lock_locomotion = bool(row["lock"])
		attack.damage_drone = float(row["damage_drone"])
		attack.damage_building = float(row["damage_building"])
		attack.damage_per_second = bool(row["dps"])
		attack.impulse_drone = float(row["impulse"])
		attack.query_shape = _build_shape(row["shape"] as Array)
		attack.query_layers = int(row["layers"])
		# `docs/07` §5.1: todas las consultas corren a 0.05 s.
		attack.query_interval = 0.05
		attack.score_input = row["score_input"] as StringName
		attack.base_weight = 1.0
		attack.audio_bank = row["audio"] as StringName
		attack.telegraph = telegraph

		var path := "%s/%s.tres" % [ATTACK_DIR, attack_id]
		var err := ResourceSaver.save(attack, path)
		if err != OK:
			push_error("No se pudo guardar %s (error %d)" % [path, err])
			return []
		attacks.append(ResourceLoader.load(path, "Resource") as AttackProfile)
	return attacks


## Una ficha de telegrafía de `docs/06` §3.
func _build_telegraph(attack_id: StringName, row: Dictionary,
		audio: StringName) -> TelegraphProfile:
	var telegraph := TelegraphProfile.new()
	telegraph.resource_name = "telegraph_%s" % attack_id
	telegraph.light_color_from = row.get("from", CYAN) as Color
	telegraph.light_color_to = row.get("to", FURY) as Color
	telegraph.light_energy_from = float(row.get("energy_from", 0.2))
	telegraph.light_energy_to = float(row.get("energy_to", 1.0))
	telegraph.audio_event = audio
	telegraph.spatial_kind = int(row.get("kind", TelegraphProfile.SpatialKind.DECAL_ZONE))
	telegraph.decal_radius = float(row.get("radius", 9.0))
	telegraph.decal_grow_from = float(row.get("grow_from", 0.25))
	telegraph.guide_width = float(row.get("guide_width", 0.25))
	telegraph.hud_warning_key = "HUD_TELEGRAPH_%s" % String(attack_id).to_upper()
	return telegraph


## Forma de consulta de una fila de [constant ATTACKS].
func _build_shape(spec: Array) -> Shape3D:
	if spec.is_empty():
		return null
	match String(spec[0]):
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(spec[1])
			cylinder.height = float(spec[2])
			return cylinder
		"box":
			var box := BoxShape3D.new()
			box.size = Vector3(float(spec[1]), float(spec[2]), float(spec[3]))
			return box
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = float(spec[1])
			capsule.height = float(spec[2])
			return capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = float(spec[1])
			return sphere
	push_error("Forma de consulta desconocida: %s" % str(spec[0]))
	return null


# --------------------------------------------------------------------------
# Percepción, partes, puntos débiles y rig
# --------------------------------------------------------------------------

## Ajustes de percepción de `docs/07` §12 y `docs/06` §15.
func _build_perception() -> PerceptionProfile:
	var perception := PerceptionProfile.new()
	perception.resource_name = "ArachnodroidPerception"
	perception.hz = 10.0
	perception.noise_base = 2.0
	perception.noise_speed_factor = 0.25
	perception.filter_tau = 0.35
	perception.memory_seconds = 4.5
	perception.blind_noise_multiplier = 5.0
	perception.blind_memory_seconds = 1.5
	perception.search_radius_start = 8.0
	perception.search_radius_end = 45.0
	perception.search_seconds = 6.0
	perception.search_refresh = 2.0
	# El rayo de línea de visión sale del visor, que es la cabeza real del
	# jefe (`docs/07` §4); si estuviera desprendido queda el casco.
	perception.head_node_name = &"wp_head_visor"
	perception.head_fallback_name = &"hull"
	perception.los_mask = PhysicsLayers.QUERY_LOS
	return perception


## Las 31 entradas de `part_overrides`: 23 estructurales más 8 puntos débiles.
func _build_part_overrides() -> Dictionary:
	var overrides: Dictionary = {}
	for part_id: String in BODY_PARTS:
		var row := BODY_PARTS[part_id] as Array
		overrides[StringName(part_id)] = _part(part_id, float(row[0]), float(row[1]),
				row[2] as StringName, bool(row[3]), float(row[4]), 0.0)
	for side: String in SIDES:
		for segment: String in LEG_PARTS:
			var row := LEG_PARTS[segment] as Array
			var part_id := "leg_%s_%s" % [side, segment]
			overrides[StringName(part_id)] = _part(part_id, float(row[0]), float(row[1]),
					&"leg", bool(row[2]), float(row[3]), 0.0)
		# La rodilla es una parte propia con `armor 0.0` y peso estructural 1.
		#
		# **HP 1 200 → 1 600 (WP-23).** Era la palanca que `docs/07` §14 nombra para
		# la duración del combate: con 1 200 la pelea del bot terminaba en 342–362 s,
		# por debajo de los 390 s (6.5 min) del rango, y con 1 400 una de las tres
		# semillas seguía quedándose corta.
		#
		# **1 600 → 800 (rodillas del checkpoint 4, 2026-09-21).** El usuario jugó la
		# ronda con el rebalance del arma (`damage` 16, ×3 en punto débil = 48 por
		# acierto) y la siguió encontrando difícil, así que pidió **la mitad** de vida
		# en las rodillas. Cada rodilla pasa de 34 a **17 aciertos**; el total de los
		# ocho puntos débiles pasa de 13 600 a **10 400** (`4·800 + 1500 + 3·1900`).
		# Es la misma palanca de §14, movida en la dirección contraria y por el mismo
		# motivo que la subió: la pasada manual manda. Nada más del jefe cambia —otras
		# partes, fases, cooldowns y daños de ataque quedan igual—, así que el jefe
		# pega lo mismo y la pelea dura menos.
		overrides[StringName("wp_leg_%s_knee" % side)] = _part("wp_leg_%s_knee" % side,
				800.0, 0.0, &"leg", false, 0.0, 1.0)
	overrides[&"wp_head_visor"] = _part("wp_head_visor", 1500.0, 0.0, &"sensor",
			false, 0.0, 1.0)
	for core_id: String in CORE_IDS:
		overrides[StringName(core_id)] = _part(core_id, 1900.0, 0.0, &"core",
				false, 0.0, 1.0)
	return overrides


## Una entrada de `part_overrides`.
func _part(part_id: String, hp: float, armor: float, function: StringName,
		detachable: bool, debris_mass: float, structure_weight: float) -> EnemyPartProfile:
	var part := EnemyPartProfile.new()
	part.resource_name = part_id
	part.part_id = StringName(part_id)
	part.hp = hp
	part.armor = armor
	part.function = function
	part.detachable = detachable
	part.debris_mass = debris_mass
	part.structure_weight = structure_weight
	part.break_trauma = 0.35
	part.dust_scale = 1.0
	return part


## Los 8 puntos débiles de `docs/07` §4: **10 400 HP** en total desde el
## rebalance de rodillas del checkpoint 4 (`4·800 + 1500 + 3·1900`; el diseño
## original decía 12 000 con rodillas de 1 200 y WP-23 lo subió a 13 600).
func _build_weak_points() -> Array[WeakPointProfile]:
	var points: Array[WeakPointProfile] = []
	for side: String in SIDES:
		var knee := WeakPointProfile.new()
		knee.resource_name = "wp_leg_%s_knee" % side
		knee.weak_point_id = StringName("wp_leg_%s_knee" % side)
		knee.host_part_id = StringName("leg_%s_tibia" % side)
		# 1 200 → 1 600 (WP-23) → 800 (checkpoint 4): ver la nota de
		# `_build_part_overrides`. Este `hp` y el de la parte tienen que coincidir:
		# el `WeakPoint` lee el suyo y la parte es la que descuenta.
		knee.hp = 800.0
		knee.damage_multiplier = 3.0
		knee.conditions = [WeakPoint.Exposure.ALWAYS]
		knee.require_all = true
		knee.emissive_color = CYAN
		knee.emissive_energy = 3.0
		knee.hud_key = "WP_KNEE"
		# `docs/07` §4: la pata entera cae y el jefe se tambalea 1.2 s. El −15 %
		# de velocidad lo aplica `notify_leg_broken` al romperse la parte, que
		# tiene `function` de pata.
		knee.on_destroy = {
			"detach_part": StringName("leg_%s_femur" % side),
			"stagger_seconds": 1.2,
		}
		points.append(knee)

	var visor := WeakPointProfile.new()
	visor.resource_name = "wp_head_visor"
	visor.weak_point_id = &"wp_head_visor"
	visor.host_part_id = &"hull"
	visor.hp = 1500.0
	visor.damage_multiplier = 3.0
	visor.conditions = [WeakPoint.Exposure.WHILE_ATTACK]
	visor.require_all = true
	visor.emissive_color = CYAN
	visor.emissive_energy = 3.0
	visor.hud_key = "WP_VISOR"
	# Ceguera temporal de 20 s y `head_laser` bloqueado 30 s (`docs/07` §4). El
	# sensor de respaldo de los 45 s lo lleva `Arachnodroid`, con acumulador.
	visor.on_destroy = {
		"blind_seconds": 20.0,
		"lock_attacks": PackedStringArray(["head_laser"]),
		"lock_seconds": 30.0,
	}
	points.append(visor)

	for core_id: String in CORE_IDS:
		var core := WeakPointProfile.new()
		core.resource_name = core_id
		core.weak_point_id = StringName(core_id)
		core.host_part_id = &"underbelly"
		core.hp = 1900.0
		core.damage_multiplier = 3.0
		# Tres rodillas rotas **y** el dron dentro del cono de 70° desde abajo.
		# En P4 `Arachnodroid` lo abre a 110° (`cone_half_angle` 55°).
		core.conditions = [WeakPoint.Exposure.AFTER_PARTS, WeakPoint.Exposure.ANGLE_CONE]
		core.require_all = true
		core.after_parts_ids = PackedStringArray(KNEE_IDS)
		core.after_parts_count = 3
		core.cone_axis = Vector3.DOWN
		core.cone_half_angle = 35.0
		# El modelo mete los tres núcleos **dentro** de la caja del `underbelly`
		# (y ∈ [12.50, 14.00] contra y ∈ [6.50, 14.00], con x y z por dentro), así
		# que sin esto el disparo desde abajo choca con la panza y los núcleos son
		# inalcanzables: la ronda no se puede ganar. Medido en WP-23; el arreglo de
		# fondo es sacar las cajas por debajo de la panza en `docs/05` (WP-24).
		core.pierces_host = true
		core.emissive_color = MAGENTA
		core.emissive_energy = 3.0
		core.hud_key = "WP_CORE"
		# Marca declarativa: los núcleos son escalonados y dos de ellos disparan P5.
		core.on_destroy = {"staged": true}
		points.append(core)
	return points


## Ajustes del rig de patas de `docs/07` §12, con los ajustes de marcha de
## WP-24d anotados uno a uno (antes → después → qué corrige).
func _build_leg_rig() -> LegRigProfile:
	var rig := LegRigProfile.new()
	rig.resource_name = "ArachnodroidLegRig"
	# 3.5 → 3.0 m: con el reposo del pie 5.0 m más afuera, cada metro de deriva
	# longitudinal cuesta más cadena. Con 3.0 la rodilla no baja de 8.6 m ni en
	# el instante de apoyar, que es donde la pata está más estirada.
	rig.step_trigger = 3.0
	# Nuevo en WP-24d: girando en el sitio el pie deriva de costado, justo donde
	# la pata ya nace separada 4.2 m, y 3.5 m de deriva dejaban el tobillo a
	# 7.3 m de la cadera en horizontal. Con 1.6 m el giro son pasos cortos.
	rig.turn_step_trigger = 1.6
	# 0.85 → 0.95: con la zancada centrada el tramo cadera→tobillo llega al 87 %
	# de la cadena en llano y al 94 % en rampa, así que a 0.85 las cuatro patas
	# pedían turno en cada tick de la rampa y la marcha se volvía un forcejeo.
	rig.reach_trigger = 0.95
	# 0.55 → 0.80 s: 1.8 trancos por segundo y por pata era un ritmo de insecto
	# para 900 t. Con 0.80 s el ciclo dura 1.97 s y un par apoya cada 0.98 s.
	rig.step_duration = 0.80
	# 3.0 → 3.5 m: con la zancada larga de WP-24d un arco de 3 m se leía plano.
	rig.step_height_min = 3.5
	rig.step_height_bias = 2.0
	rig.speed_ref = 6.0
	rig.speed_clamp = Vector2(0.6, 1.8)
	rig.stretch_max = 1.15
	# 0.6 → 0.75: el cuerpo seguía la rampa de 20° a 12° y los 8° de desajuste
	# los pagaba el par de abajo, que se quedaba recto como un puntal. A 15° la
	# rampa sigue dentro de la banda [8°, 16°] de `docs/06` §16.2.
	rig.tilt_blend = 0.75
	# 4.0 → 6.0 s⁻¹: para que el balanceo del ciclo no llegue amortiguado.
	rig.tilt_smooth_rate = 6.0
	rig.height_smooth_rate = 4.0
	rig.foot_ray_span = 40.0
	rig.foot_ray_mask = PhysicsLayers.QUERY_FOOT
	rig.crush_damage = 900.0
	rig.leap_tuck_time = 0.5
	rig.tripod_min_planted = 2
	# Ajustes que agrega WP-17 al rig procedural (`docs/06` §8.3, §8.5 y §8.6).
	# 1.5 radial → 4.2 lateral: el ensanchamiento radial movía los pies hacia
	# adelante y hacia atrás (las patas están en ∓11.625 de Z y ±6 de X), no
	# hacia afuera. El tobillo quedaba a 2.5 m de la cadera, la cadena colgaba
	# casi vertical y la rodilla se quedaba a 7.9 m, bajo la panza. Con 4.2 m
	# laterales el tobillo queda a 4.6 m y la rodilla sube a 9.1–9.6 m.
	rig.stance_spread = 5.0
	rig.body_smoothing = 4.0
	rig.drag_speed_factor = 0.55
	rig.jump_max_distance = 60.0
	rig.jump_max_height = 25.0
	rig.land_predict = 0.35
	rig.land_stagger = 0.35
	rig.leap_gravity = 9.81
	rig.leap_max_step = 1.2
	rig.rebalance_time = 1.2
	rig.downed_hip_factor = 0.35
	# Caído, el cuerpo apoya la panza en el suelo: con la cara inferior de
	# `underbelly` a +6.5 local, −6.0 deja 0.5 m de margen y los tres núcleos a
	# ~6.5 m del suelo, alcanzables de costado (WP-19b).
	rig.downed_body_height = -6.0
	rig.stagger_wobble = 4.0
	rig.stagger_frequency = 5.0
	# Peso y cadencia de la marcha (WP-24d). Todo lo de acá abajo es nuevo: sin
	# ello el coloso caminaba sin acento, se quedaba como una estatua al pararse
	# y aterrizaba de un salto de 60 m sin doblar una rodilla.
	rig.body_bob = 0.02
	rig.gait_roll = 2.0
	rig.gait_pitch = 1.5
	rig.gait_blend_time = 0.45
	rig.idle_breath = 0.15
	rig.idle_breath_hz = 0.30
	rig.land_crouch = 0.12
	rig.land_crouch_time = 0.30
	rig.climb_pitch = 25.0
	return rig


# --------------------------------------------------------------------------
# Fases (`docs/07` §6)
# --------------------------------------------------------------------------

## Las 5 fases de `docs/07` §6, en orden y monótonas.
func _build_phases() -> Array[Dictionary]:
	return [
		{
			"id": &"p1_siege",
			# Sin condición: es la fase base.
			"when": {},
			# P1 **no** declara `emissive_color`: los emisivos que trae el `.vox`
			# ya son el cian y el ámbar de la fase de asedio, y recolorearlos al
			# aparecer aplanaría la paleta del modelo.
			"then": _effects("p1_siege"),
		},
		{
			"id": &"p2_alert",
			"when": {
				"parts_broken_from": KNEE_IDS,
				"parts_broken_from_count": 1,
				"structure_below": 0.75,
				"require_all": false,
			},
			"then": _effects("p2_alert"),
		},
		{
			"id": &"p3_fury",
			"when": {
				"parts_broken_from": KNEE_IDS,
				"parts_broken_from_count": 2,
				"weak_points_broken": ["wp_head_visor"],
				"require_all": false,
			},
			"then": _effects("p3_fury", {
				"emissive_color": FURY,
				"music_stem": &"combat",
			}),
		},
		{
			"id": &"p4_belly",
			"when": {
				"parts_broken_from": KNEE_IDS,
				"parts_broken_from_count": 3,
			},
			# `open_carapace`, `core_cone_half_angle` y `gait` son claves extra
			# que `EnemyBase` ignora y `Arachnodroid` lee (`docs/07` §6): la
			# carcasa rota 70° sobre su bisagra y el cono del vientre se abre a
			# 110°.
			"then": _effects("p4_belly", {
				"open_carapace": true,
				"core_cone_half_angle": 55.0,
				"gait": &"TRIPOD",
			}),
		},
		{
			"id": &"p5_selfdestruct",
			"when": {
				"parts_broken_from": CORE_IDS,
				"parts_broken_from_count": 2,
			},
			# `defeat` **no** va acá: en P5 la derrota la dispara el temporizador
			# de 45 s al expirar (`docs/07` §6). Entrar en la fase no mata al
			# jefe, y romperle el tercer núcleo antes lo mata **sin** detonar.
			"then": _effects("p5_selfdestruct", {
				"emissive_color": SELFDESTRUCT,
				# El mismo 45.0 de `Arachnodroid.SELFDESTRUCT_SECONDS`, escrito a
				# mano: referenciar la constante arrastraría a esta herramienta
				# —que corre con `-s`, sin escena— todo el árbol de scripts del
				# jefe y sus autoloads.
				"selfdestruct_seconds": 45.0,
				"emissive_pulse": true,
			}),
		},
	]


## Bloque `then` de la fase [param phase_id], con [param extra] encima.
func _effects(phase_id: String, extra: Dictionary = {}) -> Dictionary:
	var effects: Dictionary = {
		"multipliers": MULTIPLIERS[phase_id],
		"utility_weights": UTILITY[phase_id],
	}
	var unlocks := UNLOCKS[phase_id] as Array
	if not unlocks.is_empty():
		effects["unlock_attacks"] = unlocks
	var locks := LOCKS[phase_id] as Array
	if not locks.is_empty():
		effects["lock_attacks"] = locks
	for key: String in extra:
		effects[key] = extra[key]
	return effects
