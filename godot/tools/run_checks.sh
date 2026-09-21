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
#   bash godot/tools/run_checks.sh --headless-only     # modo CI: solo los headless
#   RUN_WINDOWED=0 bash godot/tools/run_checks.sh      # lo mismo, por variable
#   bash godot/tools/run_checks.sh -- --raro           # `--` corta las banderas
#
# Codigos de salida: 0 todo en verde, 1 fallo algun check, 2 error de uso
# (bandera desconocida, mas de un nombre, nombre inexistente o incompatible con
# --headless-only) y 3 no se ejecuto ningun paso.

set -u

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
OUT_DIR="$TOOLS_DIR/out"
REPORT="$OUT_DIR/report.txt"
GODOT="${GODOT:-godot}"
# Timeout externo por proceso (segundos), ver run_checks.ps1.
PROCESS_TIMEOUT="${PROCESS_TIMEOUT:-420}"
# Suma los checks extendidos (lentos) al final: RUN_EXTENDED=1.
RUN_EXTENDED="${RUN_EXTENDED:-0}"

# Modo sin ventana, el que usa CI (docs/15 seccion 7.2). El contenedor de CI no
# trae Vulkan y el proyecto es Forward+: bajo xvfb los checks con ventana no
# arrancan. Con --headless-only (o RUN_WINDOWED=0) se saltan WINDOWED y EXTENDED
# y el resumen los lista como locales; quien tenga GPU los corre sin la bandera.
# El catalogo no cambia: la bandera solo elige que listas se recorren.
HEADLESS_ONLY=0
if [ "${RUN_WINDOWED:-1}" = "0" ]; then
	HEADLESS_ONLY=1
fi

usage() {
	echo "uso: run_checks.sh [--headless-only] [--] [<nombre_del_check>]" >&2
	echo "     RUN_WINDOWED=0 equivale a --headless-only; RUN_EXTENDED=1 suma los extendidos" >&2
}

# Un nombre de check suelto sigue siendo posicional (compatible con el uso de
# siempre) y las banderas pueden ir antes o despues de el, pero se acepta uno
# solo: dos nombres eran un error silencioso que se quedaba con el ultimo.
# Despues de `--` no se parsean mas banderas, asi que lo que venga se toma como
# nombre de check (y el catalogo lo rechaza mas abajo si no existe).
ONLY=""
HAVE_ONLY=0
NO_MORE_FLAGS=0
while [ "$#" -gt 0 ]; do
	if [ "$NO_MORE_FLAGS" = "0" ]; then
		case "$1" in
			--headless-only) HEADLESS_ONLY=1; shift; continue ;;
			--) NO_MORE_FLAGS=1; shift; continue ;;
			-*)
				echo "opcion desconocida: $1" >&2
				usage
				exit 2
				;;
		esac
	fi
	if [ "$HAVE_ONLY" = "1" ]; then
		echo "solo se acepta un nombre de check por corrida: ya estaba '$ONLY' y llego '$1'" >&2
		usage
		exit 2
	fi
	ONLY="$1"
	HAVE_ONLY=1
	shift
done

# ---------------------------------------------------------------------------
# Catalogo de checks (docs/15 seccion 3). Cada WP agrega el suyo a estas listas.
# ---------------------------------------------------------------------------

# Checks headless puros: son los que CI corre sin discusion.
HEADLESS=(project_check loading_check settings_check city_import_check enemy_import_check flight_bench flight_check controls_check pause_check hud_projection_check audio_check enemy_parts_check weapon_check energy_check city_check gait_check round_check ai_check combat_hud_check arachnodroid_check vfx_check overlay_check shake_check)   # WP-01, WP-02, WP-03, WP-13, WP-12b, WP-04, WP-05

# Checks que necesitan framebuffer real (capturas, docs/15 seccion 3.1). Corren
# bajo xvfb-run cuando no hay display.
WINDOWED=(ui_smoke_test boot_check menu_shots_check render_check)   # WP-02, WP-25, WP-24a

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
EXTRA_ARGS[menu_shots_check]="--shots=tools/out/shots"

# ---------------------------------------------------------------------------

contains() {
	local needle="$1"; shift
	local item
	for item in "$@"; do
		[ "$item" = "$needle" ] && return 0
	done
	return 1
}

# --- Validacion del nombre pedido -------------------------------------------
# Sin esto, pedir un check que la bandera excluye (o uno que no existe) salia en
# verde sin correr nada: "TODOS LOS CHECKS EN VERDE (0 pasos)" y salida 0.
# Va antes del mkdir para que un error de uso no trunque el report.txt anterior.

if [ -n "$ONLY" ] && [ "$ONLY" != "editor" ]; then
	if contains "$ONLY" "${WINDOWED[@]:-}"; then
		if [ "$HEADLESS_ONLY" = "1" ]; then
			echo "$ONLY es un check con ventana: no corre con --headless-only (ni con RUN_WINDOWED=0)" >&2
			echo "correlo sin la bandera, o bajo xvfb-run si no hay display" >&2
			exit 2
		fi
	elif contains "$ONLY" "${EXTENDED[@]:-}"; then
		if [ "$HEADLESS_ONLY" = "1" ]; then
			echo "$ONLY es un check extendido: no corre con --headless-only (ni con RUN_WINDOWED=0)" >&2
			exit 2
		fi
	elif ! contains "$ONLY" "${HEADLESS[@]:-}"; then
		echo "no existe ningun check llamado '$ONLY' en el catalogo (docs/15 seccion 3)" >&2
		usage
		exit 2
	fi
fi

mkdir -p "$OUT_DIR"
printf 'Drone Survivor - run_checks %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$REPORT"

FAILED=()
PASSED=0
# Pasos realmente ejecutados: si queda en 0 no hubo corrida que evaluar.
RAN=0

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
	RAN=$((RAN + 1))
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

	RAN=$((RAN + 1))
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
if [ "$HEADLESS_ONLY" = "0" ]; then
	for name in "${WINDOWED[@]:-}"; do
		[ -n "$name" ] && run_check "$name" 1
	done
	for name in "${EXTENDED[@]:-}"; do
		if [ -n "$name" ] && { [ "$RUN_EXTENDED" = "1" ] || [ "$ONLY" = "$name" ]; }; then
			run_check "$name" 0
		fi
	done
fi

# --- 3) Resumen y codigo de salida ---

echo
if [ "$HEADLESS_ONLY" = "1" ]; then
	LOCAL_LINE="Solo headless (--headless-only): quedan como locales ${WINDOWED[*]:-} ${EXTENDED[*]:-}"
	echo "$LOCAL_LINE"
	printf '\n===== solo headless =====\n%s\n' "$LOCAL_LINE" >> "$REPORT"
fi

if [ "$RAN" -eq 0 ]; then
	NOTHING="NO SE EJECUTO NINGUN PASO: revisa el nombre del check y las banderas"
	echo "$NOTHING"
	echo "Detalle: $REPORT"
	printf '\n===== resumen =====\n%s\n' "$NOTHING" >> "$REPORT"
	exit 3
fi

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
