#!/usr/bin/env bash
# Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
#
# Equivalente Linux de tools/run_checks.ps1 (docs/15 seccion 7.1): misma lista,
# mismo orden y mismo contrato de codigo de salida. Es el que corre el job
# `checks` del workflow de CI.
#
# Uso, desde cualquier directorio:
#   bash godot/tools/run_checks.sh
#   bash godot/tools/run_checks.sh project_check
#   GODOT=/ruta/a/godot bash godot/tools/run_checks.sh
#   RUN_EXTENDED=1 bash godot/tools/run_checks.sh      # suma balance_check (~9 min)

set -u

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
OUT_DIR="$TOOLS_DIR/out"
REPORT="$OUT_DIR/report.txt"
GODOT="${GODOT:-godot}"
ONLY="${1:-}"
# Timeout externo por proceso (segundos), ver run_checks.ps1.
PROCESS_TIMEOUT="${PROCESS_TIMEOUT:-420}"
# Suma los checks extendidos (lentos) al final: RUN_EXTENDED=1.
RUN_EXTENDED="${RUN_EXTENDED:-0}"

# ---------------------------------------------------------------------------
# Catalogo de checks (docs/15 seccion 3). Cada WP agrega el suyo a estas listas.
# ---------------------------------------------------------------------------

# Checks headless puros: son los que CI corre sin discusion.
HEADLESS=(project_check loading_check settings_check city_import_check enemy_import_check flight_bench flight_check controls_check pause_check hud_projection_check audio_check enemy_parts_check weapon_check energy_check city_check gait_check round_check ai_check combat_hud_check arachnodroid_check)   # WP-01, WP-02, WP-03, WP-13, WP-12b, WP-04, WP-05

# Checks que necesitan framebuffer real (capturas, docs/15 seccion 3.1). Corren
# bajo xvfb-run cuando no hay display.
WINDOWED=(ui_smoke_test boot_check render_check)   # WP-02, WP-24a

# Extendidos: lentos (minutos); corren solo con RUN_EXTENDED=1 o como unico check.
EXTENDED=(balance_check)   # WP-23

# Timeout externo por proceso para los checks que superan el general.
declare -A PROCESS_TIMEOUTS=()
PROCESS_TIMEOUTS[balance_check]=1800

# Informativos: reportan pero no cuentan para el codigo de salida.
# render_check necesita GPU real: en CI (xvfb, sin Vulkan) solo informa.
NON_BLOCKING=(render_check)

# Argumentos de ventana propios (en vez de --windowed --resolution 960x540).
declare -A WINDOW_ARGS=()
WINDOW_ARGS[render_check]="--windowed --resolution 1920x1080 --disable-vsync"

# Argumentos de usuario extra por check, despues de "--".
declare -A EXTRA_ARGS=()
EXTRA_ARGS[ui_smoke_test]="--shots=tools/out/shots"
EXTRA_ARGS[boot_check]="--shots=tools/out/shots"
EXTRA_ARGS[loading_check]="--timeout=120"
EXTRA_ARGS[weapon_check]="--timeout=240"
EXTRA_ARGS[ai_check]="--timeout=300"
EXTRA_ARGS[balance_check]="--timeout=1500"
EXTRA_ARGS[render_check]="--shots=tools/out/shots"

# ---------------------------------------------------------------------------

mkdir -p "$OUT_DIR"
printf 'Drone Survivor - run_checks %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$REPORT"

FAILED=()
PASSED=0

contains() {
	local needle="$1"; shift
	local item
	for item in "$@"; do
		[ "$item" = "$needle" ] && return 0
	done
	return 1
}

# --- 0) Importacion previa en frio, sin evaluar la salida (ver run_checks.ps1) ---

if [ -z "$ONLY" ] || [ "$ONLY" = "editor" ]; then
	echo "== import previo =="
	printf '
===== import previo (no evaluado) =====
' >> "$REPORT"
	set +e
	PRE_OUT="$("$GODOT" --headless --path "$PROJECT_DIR" --import 2>&1)"
	PRE_CODE=$?
	set -e
	printf '%s
' "$PRE_OUT" >> "$REPORT"
	echo "  hecho (salida $PRE_CODE)"
fi

# --- 1) El proyecto abre en el editor sin errores (docs/02 comprobacion 13) ---

if [ -z "$ONLY" ] || [ "$ONLY" = "editor" ]; then
	echo "== editor --quit =="
	printf '\n===== editor --quit =====\n' >> "$REPORT"
	set +e
	EDITOR_OUT="$("$GODOT" --headless --path "$PROJECT_DIR" --editor --quit 2>&1)"
	EDITOR_CODE=$?
	set -e
	printf '%s\n' "$EDITOR_OUT" >> "$REPORT"
	BAD="$(printf '%s\n' "$EDITOR_OUT" | grep -E '^(ERROR:|SCRIPT ERROR:)' || true)"
	if [ "$EDITOR_CODE" -ne 0 ] || [ -n "$BAD" ]; then
		echo "  FALLA: el proyecto no abre limpio (salida $EDITOR_CODE)"
		printf '%s\n' "$BAD" | sed 's/^/    /'
		FAILED+=("editor")
	else
		echo "  OK"
		PASSED=$((PASSED + 1))
	fi
fi

# --- 2) Cada check del catalogo ---

run_check() {
	local name="$1"
	local windowed="$2"

	if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then
		return 0
	fi

	echo "== $name =="
	printf '\n===== %s =====\n' "$name" >> "$REPORT"

	if [ ! -f "$TOOLS_DIR/$name.tscn" ]; then
		echo "  FALLA: no existe tools/$name.tscn"
		echo "no existe la escena del check" >> "$REPORT"
		FAILED+=("$name")
		return 0
	fi

	local proc_timeout="${PROCESS_TIMEOUTS[$name]:-$PROCESS_TIMEOUT}"
	local cmd=(timeout --kill-after=10 "$proc_timeout" "$GODOT")
	if [ "$windowed" = "1" ]; then
		if [ -z "${DISPLAY:-}" ] && command -v xvfb-run > /dev/null 2>&1; then
			cmd=(timeout --kill-after=10 "$proc_timeout" xvfb-run -a "$GODOT")
		fi
		if [ -n "${WINDOW_ARGS[$name]:-}" ]; then
			# shellcheck disable=SC2206
			local wargs=(${WINDOW_ARGS[$name]})
			cmd+=("${wargs[@]}")
		else
			cmd+=(--windowed --resolution 960x540)
		fi
	else
		cmd+=(--headless)
	fi
	cmd+=(--path "$PROJECT_DIR" "res://tools/$name.tscn")
	if [ -n "${EXTRA_ARGS[$name]:-}" ]; then
		# shellcheck disable=SC2206
		local extra=(${EXTRA_ARGS[$name]})
		cmd+=(-- "${extra[@]}")
	fi

	set +e
	local output
	output="$("${cmd[@]}" 2>&1)"
	local code=$?
	set -e
	if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		output="$output"$'
'"  FAIL: timeout externo de $proc_timeout s (el proceso no termino)"
	fi
	printf '%s\n' "$output" >> "$REPORT"
	printf '%s\n' "$output" | grep -E '^(  FAIL:|CHECK )' | sed 's/^/  /' || true

	if [ "$code" -eq 0 ]; then
		PASSED=$((PASSED + 1))
	elif contains "$name" "${NON_BLOCKING[@]}"; then
		echo "  (informativo, no bloquea; salida $code)"
	else
		echo "  FALLA (salida $code)"
		FAILED+=("$name")
	fi
}

for name in "${HEADLESS[@]:-}"; do
	[ -n "$name" ] && run_check "$name" 0
done
for name in "${WINDOWED[@]:-}"; do
	[ -n "$name" ] && run_check "$name" 1
done
for name in "${EXTENDED[@]:-}"; do
	if [ -n "$name" ] && { [ "$RUN_EXTENDED" = "1" ] || [ "$ONLY" = "$name" ]; }; then
		run_check "$name" 0
	fi
done

# --- 3) Resumen y codigo de salida ---

echo
if [ "${#FAILED[@]}" -eq 0 ]; then
	SUMMARY="TODOS LOS CHECKS EN VERDE ($PASSED pasos)"
else
	SUMMARY="FALLARON ${#FAILED[@]} de $((${#FAILED[@]} + PASSED)): ${FAILED[*]}"
fi
echo "$SUMMARY"
echo "Detalle: $REPORT"
printf '\n===== resumen =====\n%s\n' "$SUMMARY" >> "$REPORT"

[ "${#FAILED[@]}" -eq 0 ] || exit 1
exit 0
