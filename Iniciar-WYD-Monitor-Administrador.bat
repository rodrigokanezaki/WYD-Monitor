@echo off
setlocal
set "WYD_LAUNCHER=%~dp0Iniciar-WYD-Monitor.bat"
echo O Windows pedira permissao para abrir o monitor como administrador.
powershell.exe -NoProfile -Command "try { Start-Process -FilePath $env:WYD_LAUNCHER -Verb RunAs -ErrorAction Stop } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 pause
