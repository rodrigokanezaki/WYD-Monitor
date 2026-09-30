@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Acesso-Celular.ps1"
if errorlevel 1 (pause & exit /b 1)
start "" notepad.exe "%LOCALAPPDATA%\WYDMonitor\Acesso-Celular.txt"
