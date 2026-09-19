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

set -u

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
OUT_DIR="$TOOLS_DIR/out"
REPORT="$OUT_DIR/report.txt"
GODOT="${GODOT:-godot}"
ONLY="${1:-}"
# Timeout externo por proceso (segundos), ver run_checks.ps1.
PROCESS_TIMEOUT="${PROCESS_TIMEOUT:-420}"

# ---------------------------------------------------------------------------
# Catalogo de checks (docs/15 seccion 3). Cada WP agrega el suyo a estas listas.
# ---------------------------------------------------------------------------

# Checks headless puros: son los que CI corre sin discusion.
HEADLESS=(project_check loading_check settings_check city_import_check enemy_import_check flight_bench flight_check controls_check pause_check hud_projection_check audio_check)   # WP-01, WP-02, WP-03, WP-13, WP-12b, WP-04, WP-05

# Checks que necesitan framebuffer real (capturas, docs/15 seccion 3.1). Corren
# bajo xvfb-run cuando no hay display.
WINDOWED=(ui_smoke_test boot_check)   # WP-02

# Informativos: reportan pero no cuentan para el codigo de salida.
NON_BLOCKING=(render_parity_check)

# Argumentos de usuario extra por check, despues de "--".
declare -A EXTRA_ARGS=()
EXTRA_ARGS[ui_smoke_test]="--shots=tools/out/shots"
EXTRA_ARGS[boot_check]="--shots=tools/out/shots"
EXTRA_ARGS[loading_check]="--timeout=120"

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

	local cmd=(timeout --kill-after=10 "$PROCESS_TIMEOUT" "$GODOT")
	if [ "$windowed" = "1" ]; then
		if [ -z "${DISPLAY:-}" ] && command -v xvfb-run > /dev/null 2>&1; then
			cmd=(timeout --kill-after=10 "$PROCESS_TIMEOUT" xvfb-run -a "$GODOT")
		fi
		cmd+=(--windowed --resolution 960x540)
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
'"  FAIL: timeout externo de $PROCESS_TIMEOUT s (el proceso no termino)"
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
