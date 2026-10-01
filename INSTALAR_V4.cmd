@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALAR_GLOBAL_V4.ps1" %*
set "router_exit=%errorlevel%"
echo.
if not "%router_exit%"=="0" echo No se pudo completar la instalacion. Revisa el error mostrado arriba.
pause
exit /b %router_exit%
