# Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
#
# Corre los checks headless del proyecto en orden, deja el detalle en
# tools/out/report.txt y devuelve 0 solo si todos pasaron (docs/15 seccion 7.1).
#
# Uso, desde la raiz del repositorio:
#   powershell -File godot/tools/run_checks.ps1
#   powershell -File godot/tools/run_checks.ps1 -Only project_check
#   powershell -File godot/tools/run_checks.ps1 -Godot "D:/Godot/godot.console.exe"
#   powershell -File godot/tools/run_checks.ps1 -Extended     # suma balance_check (~9 min)

[CmdletBinding()]
param(
    [string]$Only = "",
    [string]$Godot = "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe",
    # Timeout externo por proceso (segundos). Protege contra checks que no llegan a
    # arrancar (por ejemplo, un error de parseo en el script raiz deja el proceso vivo
    # sin escena y el timeout interno de CheckRunner nunca corre).
    [int]$ProcessTimeout = 420,
    # Suma los checks extendidos (lentos) al final de la suite.
    [switch]$Extended
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Catalogo de checks (docs/15 seccion 3). Cada WP agrega el suyo a estas listas.
# ---------------------------------------------------------------------------

# Checks headless puros: son los que CI corre sin discusion.
$Headless = @(
    "project_check",     # WP-01
    "loading_check",     # WP-02
    "settings_check",    # WP-03
    "city_import_check"  # WP-13,
    "enemy_import_check"  # WP-12b
    "flight_bench"        # WP-04
    "flight_check"        # WP-05
    "controls_check"  # WP-10
    "pause_check"  # WP-11
    "hud_projection_check"  # WP-06
    "audio_check"  # WP-07
    "enemy_parts_check"  # WP-16
    "weapon_check"  # WP-14
    "energy_check"  # WP-15
    "city_check"  # WP-20
    "gait_check"  # WP-17
    "round_check"  # WP-21
    "ai_check"  # WP-18
    "combat_hud_check"  # WP-22
    "arachnodroid_check"  # WP-19
)

# Checks que necesitan un framebuffer real porque capturan imagen (docs/15 seccion 3.1).
# En Windows corren con ventana a 960x540.
$Windowed = @(
    "ui_smoke_test",  # WP-02, ampliado en WP-09 y WP-11
    "boot_check",     # WP-02
    "menu_shots_check",  # WP-25: capturas de los menús
    "render_check"    # WP-24a: 1920x1080 sin vsync, ver $WindowArgs
)

# Extendidos: lentos (minutos), corren solo con -Extended o con -Only <nombre>.
# balance_check simula cuatro partidas completas a time_scale 4 (docs/07 seccion 14).
$ExtendedChecks = @(
    "balance_check"  # WP-23
)

# Timeout externo por proceso para los checks que superan el general.
$ProcessTimeouts = @{
    "balance_check" = 1800
}

# Informativos: reportan pero no cuentan para el codigo de salida (docs/15 seccion 8.5).
$NonBlocking = @()

# Argumentos de ventana propios (en vez de --windowed --resolution 960x540).
$WindowArgs = @{
    "render_check" = @("--windowed", "--resolution", "1920x1080", "--disable-vsync")
}

# Argumentos de usuario extra por check, despues de "--".
$ExtraArgs = @{
    "weapon_check"  = @("--timeout=240")
    "ui_smoke_test" = @("--shots=tools/out/shots")
    "boot_check"    = @("--shots=tools/out/shots")
    "loading_check" = @("--timeout=120")
    "ai_check"      = @("--timeout=300")
    "balance_check" = @("--timeout=1500")
    "render_check"  = @("--shots=tools/out/shots")
    "menu_shots_check" = @("--shots=tools/out/shots")
}

# ---------------------------------------------------------------------------

$ToolsDir = $PSScriptRoot
$ProjectDir = Split-Path -Parent $ToolsDir
$OutDir = Join-Path $ToolsDir "out"
$Report = Join-Path $OutDir "report.txt"

if (-not (Test-Path -LiteralPath $Godot)) {
    Write-Host "No se encontro el binario de Godot en: $Godot"
    Write-Host "Pasalo con -Godot <ruta> o ajusta el valor por defecto del script."
    exit 2
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ProjectArg = $ProjectDir
if ($ProjectArg -match '\s') { $ProjectArg = '"' + $ProjectArg + '"' }

function Invoke-Godot {
    param([string[]]$GodotArgs, [string]$LogName, [int]$Timeout = $ProcessTimeout)

    $outFile = Join-Path $OutDir "$LogName.stdout.tmp"
    $errFile = Join-Path $OutDir "$LogName.stderr.tmp"
    $params = @{
        FilePath               = $Godot
        ArgumentList           = $GodotArgs
        NoNewWindow            = $true
        PassThru               = $true
        RedirectStandardOutput = $outFile
        RedirectStandardError  = $errFile
    }
    $proc = Start-Process @params
    # Cachear el handle: sin esto, un Process devuelto por -PassThru sin -Wait
    # no expone ExitCode al terminar (peculiaridad de PowerShell 5.1).
    $null = $proc.Handle
    $timedOut = $false
    if (-not $proc.WaitForExit($Timeout * 1000)) {
        $timedOut = $true
        # Matar el arbol completo: el wrapper de consola lanza al Godot real como hijo.
        & taskkill.exe /F /T /PID $proc.Id 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }

    # Godot escribe UTF-8; sin -Encoding UTF8, PowerShell 5.1 lo leeria como ANSI
    # y destrozaria las tildes de los mensajes de fallo.
    $text = ""
    foreach ($file in @($outFile, $errFile)) {
        if (Test-Path -LiteralPath $file) {
            $chunk = Get-Content -LiteralPath $file -Raw -Encoding UTF8
            if ($null -ne $chunk) { $text = $text + $chunk }
            Remove-Item -LiteralPath $file -Force
        }
    }
    $code = 1
    if ($timedOut) {
        $text = $text + "`n  FAIL: timeout externo de $Timeout s (el proceso no termino; probablemente no llego a instanciar la escena del check)`n"
    }
    else {
        $proc.WaitForExit()
        $code = [int]$proc.ExitCode
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $text; TimedOut = $timedOut }
}

function Add-Report {
    param([string]$Text)
    Add-Content -Path $Report -Value $Text -Encoding utf8
}

Set-Content -Path $Report -Encoding utf8 -Value ("Drone Survivor - run_checks " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

$failed = New-Object System.Collections.ArrayList
$passed = 0

# --- 0) Importacion previa en frio, sin evaluar la salida ---
# En un checkout limpio, la primera importacion del pack de ciudad emite lineas
# ERROR: propias del pack (rutas de textura rotas, nodos sin nombre) que no se
# repiten en un proyecto ya importado. Este paso las absorbe para que el paso 1
# mida solo el estado estable (docs/10 nota de WP-13).

if ([string]::IsNullOrEmpty($Only) -or $Only -eq "editor") {
    Write-Host "== import previo =="
    Add-Report "`n===== import previo (no evaluado) ====="
    $pre = Invoke-Godot -LogName "import" -GodotArgs @("--headless", "--path", $ProjectArg, "--import")
    Add-Report $pre.Output
    Write-Host ("  hecho (salida {0})" -f $pre.ExitCode)
}

# --- 1) El proyecto abre en el editor sin errores (docs/02 comprobacion 13) ---

if ([string]::IsNullOrEmpty($Only) -or $Only -eq "editor") {
    Write-Host "== editor --quit =="
    Add-Report "`n===== editor --quit ====="
    $res = Invoke-Godot -LogName "editor" -GodotArgs @("--headless", "--path", $ProjectArg, "--editor", "--quit")
    Add-Report $res.Output
    $bad = @($res.Output -split "`r?`n" | Where-Object { $_ -match "^(ERROR:|SCRIPT ERROR:)" })
    if ($res.ExitCode -ne 0 -or $bad.Count -gt 0) {
        Write-Host ("  FALLA: el proyecto no abre limpio ({0} lineas de error, salida {1})" -f $bad.Count, $res.ExitCode)
        foreach ($line in $bad) { Write-Host "    $line" }
        [void]$failed.Add("editor")
    }
    else {
        Write-Host "  OK"
        $passed = $passed + 1
    }
}

# --- 2) Cada check del catalogo ---

$catalog = New-Object System.Collections.ArrayList
foreach ($name in $Headless) { [void]$catalog.Add([pscustomobject]@{ Name = $name; Windowed = $false }) }
foreach ($name in $Windowed) { [void]$catalog.Add([pscustomobject]@{ Name = $name; Windowed = $true }) }
foreach ($name in $ExtendedChecks) {
    if ($Extended -or $Only -eq $name) { [void]$catalog.Add([pscustomobject]@{ Name = $name; Windowed = $false }) }
}

foreach ($check in $catalog) {
    if (-not [string]::IsNullOrEmpty($Only) -and $check.Name -ne $Only) { continue }

    $scenePath = Join-Path $ToolsDir ($check.Name + ".tscn")
    Write-Host ("== {0} ==" -f $check.Name)
    Add-Report ("`n===== {0} =====" -f $check.Name)

    if (-not (Test-Path -LiteralPath $scenePath)) {
        Write-Host "  FALLA: no existe tools/$($check.Name).tscn"
        Add-Report "no existe la escena del check"
        [void]$failed.Add($check.Name)
        continue
    }

    if ($check.Windowed) {
        $godotArgs = @("--windowed", "--resolution", "960x540")
        if ($WindowArgs.ContainsKey($check.Name)) { $godotArgs = @($WindowArgs[$check.Name]) }
    }
    else {
        $godotArgs = @("--headless")
    }
    $godotArgs += @("--path", $ProjectArg, ("res://tools/{0}.tscn" -f $check.Name))
    $extra = $ExtraArgs[$check.Name]
    if ($null -ne $extra -and $extra.Count -gt 0) { $godotArgs += @("--") + $extra }

    $timeout = $ProcessTimeout
    if ($ProcessTimeouts.ContainsKey($check.Name)) { $timeout = [int]$ProcessTimeouts[$check.Name] }
    $res = Invoke-Godot -LogName $check.Name -GodotArgs $godotArgs -Timeout $timeout
    Add-Report $res.Output
    foreach ($line in ($res.Output -split "`r?`n")) {
        if ($line -match "^(\s+FAIL:|CHECK )") { Write-Host ("  " + $line.Trim()) }
    }

    if ($res.ExitCode -eq 0) {
        $passed = $passed + 1
    }
    elseif ($NonBlocking -contains $check.Name) {
        Write-Host ("  (informativo, no bloquea; salida {0})" -f $res.ExitCode)
    }
    else {
        Write-Host ("  FALLA (salida {0})" -f $res.ExitCode)
        [void]$failed.Add($check.Name)
    }
}

# --- 3) Resumen y codigo de salida ---

$summary = ""
if ($failed.Count -eq 0) {
    $summary = "TODOS LOS CHECKS EN VERDE ({0} pasos)" -f $passed
}
else {
    $summary = "FALLARON {0} de {1}: {2}" -f $failed.Count, ($failed.Count + $passed), ($failed -join ", ")
}

Write-Host ""
Write-Host $summary
Write-Host ("Detalle: {0}" -f $Report)
Add-Report ("`n===== resumen =====`n" + $summary)

if ($failed.Count -eq 0) { exit 0 }
exit 1
