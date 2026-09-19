## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name UIPalette
extends RefCounted
## Single source of truth for the interface colors and sizes.
## The menu theme is generated from these values by `tools/build_theme.gd`.


const BG := Color("#F5F6F8")
const BG_TOP := Color("#FAFBFC")
const BG_BOTTOM := Color("#E9EDF2")
const SCRIM := Color(0.961, 0.965, 0.973, 0.86)

const SURFACE := Color("#FFFFFF")
const SURFACE_ALT := Color("#F2F4F7")
const SURFACE_PRESSED := Color("#E8ECF1")
const SURFACE_DISABLED := Color("#F7F8FA")

const BORDER := Color("#DCE1E7")
const BORDER_STRONG := Color("#C5CCD5")

const TEXT := Color("#1B1F24")
const TEXT_2 := Color("#5B6470")
const TEXT_DISABLED := Color("#A0A8B3")
const TEXT_ON_ACCENT := Color("#FFFFFF")

const ACCENT := Color("#2F7CF6")
const ACCENT_HOVER := Color("#1F6BE0")
const ACCENT_PRESSED := Color("#1859C2")
const ACCENT_SOFT := Color("#E8F0FE")

const DANGER := Color("#B3261E")
const DANGER_SOFT := Color("#FDECEC")
const DANGER_HOVER := Color("#FADADA")
const DANGER_BORDER := Color("#F3B6B4")

const SUCCESS := Color("#2FA46F")
const SHADOW := Color(0.059, 0.09, 0.165, 0.08)

const GRAPH_PITCH := Color("#E5484D")
const GRAPH_ROLL := Color("#30A46C")
const GRAPH_YAW := Color("#0091FF")
const GRAPH_GRID := Color("#E6EAEE")

## In-flight HUD (white on video)
const HUD_TEXT := Color(1, 1, 1, 1)
const HUD_SHADOW := Color(0, 0, 0, 0.35)
const HUD_BOX := Color(0, 0, 0, 0.25)
const HUD_REC := Color("#FF4D3D")

const FONT_REGULAR := "res://gui/theme/fonts/RecursiveSansLnrSt-Med.otf"
const FONT_BOLD := "res://gui/theme/fonts/RecursiveSansLnrSt-Bold.otf"
const FONT_MONO := "res://gui/theme/fonts/RecursiveMonoLnrSt-Regular.otf"

const SCREEN_MARGIN_H := 72
const SCREEN_MARGIN_TOP := 56
const SCREEN_MARGIN_BOTTOM := 104
