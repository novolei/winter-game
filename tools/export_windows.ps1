$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$godot = "D:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe"
$output = Join-Path $projectRoot "build\windows\WinterTime.exe"
$archive = Join-Path $projectRoot "build\windows\WinterTime-Windows.zip"

if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 console executable was not found at: $godot"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

& $godot --headless --path $projectRoot --import
if ($LASTEXITCODE -ne 0) { throw "Godot asset import failed." }

Push-Location $projectRoot
try {
    bash tools/run_tests.sh
    if ($LASTEXITCODE -ne 0) { throw "The test suite failed; export was cancelled." }
} finally {
    Pop-Location
}

& $godot --headless --path $projectRoot --export-release "Windows Desktop" $output
if ($LASTEXITCODE -ne 0) { throw "Windows export failed." }

Compress-Archive -LiteralPath $output -DestinationPath $archive -CompressionLevel Optimal -Force

Write-Host "Windows build ready: $output" -ForegroundColor Green
Write-Host "Shareable archive ready: $archive" -ForegroundColor Green
