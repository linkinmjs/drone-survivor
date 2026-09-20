## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Catálogo estático de enemigos (`docs/06` §12 y §14).
##
## El `RoundManager` (`docs/11`) instancia **exclusivamente** desde acá: nadie
## carga una escena de enemigo por ruta. Como en [RoundCatalog], el id es para
## siempre, porque es la clave con la que la ronda referencia a su jefe.
##
## El MVP tiene un solo enemigo; los ocho restantes son P3 (`docs/14`).
class_name EnemyCatalog extends RefCounted

## Entradas del catálogo: id → `{scene, profile, display_key}` con rutas `res://`.
const ENTRIES: Dictionary[StringName, Dictionary] = {
	&"arachnodroid": {
		"scene": "res://enemies/arachnodroid/arachnodroid.tscn",
		"profile": "res://enemies/arachnodroid/profiles/arachnodroid_profile.tres",
		"display_key": "ENEMY_ARACHNODROID",
	},
}


## `true` si [param id] está en el catálogo.
static func has_id(id: StringName) -> bool:
	return ENTRIES.has(id)


## Entrada de [param id], o un diccionario vacío si no existe.
static func entry(id: StringName) -> Dictionary:
	return ENTRIES.get(id, {}) as Dictionary


## Escena instanciable de [param id], o `null` si no existe o no carga.
static func scene_of(id: StringName) -> PackedScene:
	var path := String(entry(id).get("scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("EnemyCatalog: no hay escena para '%s'." % id)
		return null
	return ResourceLoader.load(path, "PackedScene") as PackedScene


## Ficha de [param id], o `null` si no existe o no carga.
static func profile_of(id: StringName) -> EnemyProfile:
	var path := String(entry(id).get("profile", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("EnemyCatalog: no hay perfil para '%s'." % id)
		return null
	return ResourceLoader.load(path, "Resource") as EnemyProfile


## Clave de traducción `ENEMY_*` de [param id].
static func display_key(id: StringName) -> String:
	return String(entry(id).get("display_key", ""))


## Ids del catálogo, en orden de declaración.
static func ids() -> PackedStringArray:
	var found := PackedStringArray()
	for id: StringName in ENTRIES:
		found.append(String(id))
	return found
