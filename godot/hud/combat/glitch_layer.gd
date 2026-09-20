## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Perturbación de interfaz por EMP (`docs/12` §4.3).
##
## `EnergySystem.emp_hit(glitch_seconds)` —señal **local**, no del bus
## (`docs/09` §2.9)— arranca una perturbación de intensidad `e = 1 − t / glitch_seconds`
## que dura exactamente los segundos pedidos:
##
## - cada componente recibe un desplazamiento de ±`6 · e` px, re-sorteado a 12 Hz;
## - con probabilidad `0.15 · e` por sorteo, un componente al azar se saltea un cuadro;
## - con probabilidad `0.20 · e`, los números se dibujan como `--`;
## - [member emp_strength] publica `e` para el uniform del `fpv_overlay.gdshader`
##   (`docs/13` §), de modo que el glitch de la imagen y el del HUD están **en fase**
##   por construcción y no por dos temporizadores que hay que sincronizar.
##
## Un segundo EMP durante el primero **reinicia** el contador, no lo acumula
## (`docs/12` §4.3): si se sumaran, tres pulsos seguidos dejarían el HUD ilegible
## medio minuto y el jugador no tendría forma de entender por qué.
##
## Este componente no dibuja nada: escribe en los demás. Es un [CombatHUDComponent] y
## no un [Node] suelto para que viva en el mismo árbol, se apague con el modo
## cinemático y comparta el reloj manual del `CombatHUD`, que es lo que le permite a
## `combat_hud_check` medir los 3.0 s con una tolerancia de 0.1.
class_name HUDGlitchLayer
extends CombatHUDComponent

## Desplazamiento máximo, en píxeles (`docs/12` §8).
const MAX_OFFSET: float = 6.0

## Frecuencia de re-sorteo, en Hz (`docs/12` §8).
const SAMPLE_HZ: float = 12.0

## Probabilidad, por sorteo y a intensidad plena, de saltear un componente un cuadro.
const BLANK_CHANCE: float = 0.15

## Probabilidad, por sorteo y a intensidad plena, de romper los números.
const SCRAMBLE_CHANCE: float = 0.20

## Intensidad del EMP, de 1 a 0. La lee `docs/13` para el uniform del overlay FPV.
var emp_strength: float = 0.0

## Componentes a los que se les escribe la perturbación.
var _targets: Array[CombatHUDComponent] = []

var _left: float = 0.0
var _duration: float = 0.0
var _sample: float = 0.0
var _scramble: bool = false
var _blank_index: int = -1
var _blank_frames: int = 0
var _offsets: Array[Vector2] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _setup() -> void:
	# Semilla derivada de la ronda: dos partidas con la misma `Global.round_seed`
	# sacuden el HUD igual, que es lo que `docs/15` §1.1 pide de cualquier captura.
	_rng.seed = hash("emp_glitch") ^ Global.round_seed


## Da de alta los componentes que el EMP puede mover. [CombatHUD] la llama una vez.
func set_targets(targets: Array[CombatHUDComponent]) -> void:
	_targets = targets.duplicate()
	_offsets.resize(_targets.size())
	_offsets.fill(Vector2.ZERO)
	_apply()


## `EnergySystem.emp_hit`. Reinicia el contador: no acumula.
func trigger_emp(glitch_seconds: float) -> void:
	if not is_finite(glitch_seconds) or glitch_seconds <= 0.0:
		return
	_duration = glitch_seconds
	_left = glitch_seconds
	_sample = 0.0
	emp_strength = 1.0
	_resample()
	_apply()


## `true` mientras haya perturbación. Es `false` a los `glitch_seconds` exactos.
func is_glitching() -> bool:
	return _left > 0.0


## Segundos que le quedan al glitch.
func remaining() -> float:
	return maxf(_left, 0.0)


## Corta el EMP y devuelve todos los desplazamientos a [constant Vector2.ZERO].
func stop() -> void:
	_left = 0.0
	_duration = 0.0
	_sample = 0.0
	emp_strength = 0.0
	_scramble = false
	_blank_index = -1
	_blank_frames = 0
	_offsets.fill(Vector2.ZERO)
	for target: CombatHUDComponent in _targets:
		if is_instance_valid(target):
			target.clear_glitch()


func _tick(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(_left - delta, 0.0)
	if _left <= 0.0:
		stop()
		return
	emp_strength = clampf(_left / maxf(_duration, 0.001), 0.0, 1.0)
	_sample += delta
	var period := 1.0 / SAMPLE_HZ
	while _sample >= period:
		_sample -= period
		_resample()
	_apply()
	if _blank_frames > 0:
		_blank_frames -= 1
		if _blank_frames <= 0:
			_blank_index = -1


# --- Internos ---------------------------------------------------------------------------------

## Sortea desplazamientos, números rotos y el componente que se saltea un cuadro.
func _resample() -> void:
	var amplitude := MAX_OFFSET * emp_strength
	for index: int in _offsets.size():
		_offsets[index] = Vector2(_rng.randf_range(-amplitude, amplitude),
				_rng.randf_range(-amplitude, amplitude))
	_scramble = _rng.randf() < SCRAMBLE_CHANCE * emp_strength
	if not _targets.is_empty() and _rng.randf() < BLANK_CHANCE * emp_strength:
		_blank_index = _rng.randi_range(0, _targets.size() - 1)
		_blank_frames = 1
	else:
		_blank_index = -1
		_blank_frames = 0


func _apply() -> void:
	for index: int in _targets.size():
		var target := _targets[index]
		if not is_instance_valid(target):
			continue
		var offset := _offsets[index] if index < _offsets.size() else Vector2.ZERO
		target.apply_glitch(offset, _scramble, index == _blank_index)
