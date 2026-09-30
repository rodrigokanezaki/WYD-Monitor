@echo off
setlocal
cd /d "%~dp0"
if not exist "%LOCALAPPDATA%\WYDMonitor" mkdir "%LOCALAPPDATA%\WYDMonitor"
set "ERRFILE=%LOCALAPPDATA%\WYDMonitor\WYD-Monitor-Erro.txt"
rem Testa a gravacao antes de redirecionar o PowerShell.
type nul > "%ERRFILE%" 2>nul
if errorlevel 1 (
    set "ERRFILE=%TEMP%\WYD-Monitor-Erro.txt"
)
type nul > "%ERRFILE%" 2>nul
if errorlevel 1 goto log_failure
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WYD-Monitor.ps1" 2> "%ERRFILE%"
set "MONITOR_EXIT=%ERRORLEVEL%"
if not "%MONITOR_EXIT%"=="0" goto monitor_failure
for %%A in ("%ERRFILE%") do if %%~zA GTR 0 goto monitor_failure
del "%ERRFILE%"
exit /b 0
:monitor_failure
echo.
echo O WYD Monitor encontrou um erro. Codigo de saida: %MONITOR_EXIT%
echo Relatorio: "%ERRFILE%"
type "%ERRFILE%"
pause
exit /b 1
:log_failure
echo Nao foi possivel criar o log na pasta do monitor nem em TEMP.
echo Verifique as permissoes dessas pastas.
pause
exit /b 1
