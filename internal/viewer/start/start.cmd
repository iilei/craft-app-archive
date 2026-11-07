@echo off
rem Start the Craft Wiki viewer on Windows (double-click in Explorer).
rem Paths are resolved from this script's location, so the archive folder can be
rem moved or copied anywhere.
setlocal
set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"
set "VIEWER=%~dp0launchers\windows-%ARCH%\craft-wiki-viewer.exe"
if not exist "%VIEWER%" (
  echo No viewer for windows-%ARCH% in this archive: "%VIEWER%"
  pause
  exit /b 1
)
"%VIEWER%" --root "%~dp0dist" %*
if errorlevel 1 pause
