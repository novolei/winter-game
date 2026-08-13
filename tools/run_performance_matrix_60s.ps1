param(
    [string]$GodotBin = 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDir = (Join-Path $env:TEMP ('winter_time_performance_' + (Get-Date -Format 'yyyyMMdd_HHmmss')))
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$activeGodot = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like 'Godot_v4.7.1*'
}
if ($activeGodot) {
    $active = ($activeGodot | ForEach-Object { "PID $($_.ProcessId): $($_.CommandLine)" }) -join "`n"
    throw "Canonical sampling requires no editor or game process. Close Godot and retry.`n$active"
}
if (-not (Test-Path -LiteralPath $GodotBin)) {
    throw "Godot console binary not found: $GodotBin"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$scenarios = @('stationary', 'shallow_straight', 'deep_straight', 'deep_diagonal')
foreach ($scenario in $scenarios) {
    $result = Join-Path $OutputDir ($scenario + '.json')
    & $GodotBin --path $ProjectPath --rendering-driver d3d12 --resolution 1600x1000 `
        res://tools/performance_matrix_60s.tscn -- --scenario $scenario --out $result
    if ($LASTEXITCODE -ne 0) {
        throw "Performance scenario failed: $scenario (exit $LASTEXITCODE)"
    }
    $json = Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
    if ($json.frames -lt 100 -or [Math]::Abs($json.wall_elapsed_seconds - 60.0) -gt 0.2) {
        throw "Performance scenario produced an incomplete result: $scenario"
    }
}

foreach ($preset in @('pale_day', 'deep_night', 'whiteout')) {
    $capture = Join-Path $OutputDir ('quality_' + $preset + '.png')
    & $GodotBin --path $ProjectPath --rendering-driver d3d12 --resolution 1600x1000 `
        res://tools/capture_visual_quality_gate.tscn -- --preset $preset --out $capture
    if ($LASTEXITCODE -ne 0) {
        throw "Visual quality gate failed: $preset (exit $LASTEXITCODE)"
    }
}

Write-Output "WinterTime canonical performance evidence: $OutputDir"
