## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
extends SceneTree
## Regenerates the menu theme from UIPalette.
## Usage: godot --headless --path godot -s res://tools/build_theme.gd


const OUTPUT := "res://gui/theme/main_theme.tres"


func _init() -> void:
	var builder := load("res://gui/theme/theme_builder.gd")
	var theme: Theme = builder.build()
	var err := ResourceSaver.save(theme, OUTPUT)
	if err != OK:
		push_error("Could not save %s (error %d)" % [OUTPUT, err])
		quit(1)
		return
	print("Theme saved to %s" % OUTPUT)
	quit(0)
