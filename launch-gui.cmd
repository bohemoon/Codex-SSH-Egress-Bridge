@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\codex-ssh-eg-gui.ps1"
if errorlevel 1 (
    echo.
    echo GUI startup failed. Review the error above.
    pause
)
