## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sol del juego: un [DirectionalLight3D] que toma su look de un [SunProfile]
## (`docs/13` §3.2).
##
## Es `@tool` para que el atardecer se vea en el editor igual que en el juego: al
## abrir la escena, o al soltar otro perfil en el inspector, la luz se reajusta sola.
##
## El nodo se llama `Sun` en todas las escenas por convención
## ([constant LevelBase.SUN_NODE]): así [method LevelBase._register_sun] lo encuentra
## y `Graphics` le aplica además la tabla de sombras del preset.
@tool
class_name SunLight
extends DirectionalLight3D

## Perfil de look. Los niveles usan `world/sun_dusk.tres`.
@export var profile: SunProfile = null:
	set(value):
		if profile == value:
			return
		_disconnect_profile()
		profile = value
		_connect_profile()
		apply_profile()


func _ready() -> void:
	_connect_profile()
	apply_profile()


func _exit_tree() -> void:
	_disconnect_profile()


## Vuelca [member profile] sobre esta luz. Sin perfil no hace nada: los valores que
## traiga la escena quedan como están.
func apply_profile() -> void:
	if profile == null:
		return
	profile.apply_to(self)


## Se reengancha al perfil para que tocarlo en el inspector se vea en el acto.
## [signal Resource.changed] sólo se emite en el editor, así que en el juego esto
## es una conexión inerte.
func _connect_profile() -> void:
	if profile == null or profile.changed.is_connected(apply_profile):
		return
	var _discard := profile.changed.connect(apply_profile)


func _disconnect_profile() -> void:
	if profile == null or not profile.changed.is_connected(apply_profile):
		return
	profile.changed.disconnect(apply_profile)
