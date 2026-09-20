## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Regenera los **dos** temas del juego desde [UIPalette] (`docs/13` §2.4).
##
## Uso:
## [codeblock]
## godot --headless --path godot --script res://tools/build_theme.gd
## [/codeblock]
##
## Antes de escribir nada verifica el contraste de todos los pares texto/fondo de
## `ThemeBuilder.CONTRAST_PAIRS` y **aborta** si alguno cae por debajo de 4,5:1 (WCAG
## 2.1 AA). Un tema que no se lee no se guarda: es la única forma de que la paleta
## oscura no se degrade a fuerza de retoques.
extends SceneTree

## Tema de menús.
const MENU_OUTPUT := "res://gui/theme/main_theme.tres"

## Tema del HUD de vuelo (`docs/12` §2.7).
const HUD_OUTPUT := "res://hud/hud_theme.tres"


func _init() -> void:
	var builder := preload("res://gui/theme/theme_builder.gd")

	var report: Dictionary = builder.verify_contrast()
	var rows: Array = report["rows"]
	var failures: Array = report["failures"]
	print("Contraste (WCAG 2.1, mínimo %.1f:1)" % builder.MIN_CONTRAST)
	for row: Dictionary in rows:
		print("  %-16s sobre %-18s %5.2f:1  %s" % [row["text"], row["background"],
				row["ratio"], "OK" if row["ratio"] >= builder.MIN_CONTRAST else "FALLA"])
	if not failures.is_empty():
		for row: Dictionary in failures:
			push_error("Contraste insuficiente: %s sobre %s es %.2f:1 (mínimo %.1f:1)"
					% [row["text"], row["background"], row["ratio"], builder.MIN_CONTRAST])
		quit(1)
		return

	if not _save(builder.build(), MENU_OUTPUT):
		quit(1)
		return
	if not _save(builder.build_hud(), HUD_OUTPUT):
		quit(1)
		return
	quit(0)


## Guarda [param theme] en [param path]. Devuelve `false` si el guardado falla.
func _save(theme: Theme, path: String) -> bool:
	var err := ResourceSaver.save(theme, path)
	if err != OK:
		push_error("No se pudo guardar %s (error %d)" % [path, err])
		return false
	print("Tema guardado en %s" % path)
	return true
