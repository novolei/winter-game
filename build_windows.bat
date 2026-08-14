@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\export_windows.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. Review the messages above.
  pause
  exit /b 1
)
echo.
echo Build complete: build\windows\WinterTime.exe
echo Share this archive: build\windows\WinterTime-Windows.zip
pause
