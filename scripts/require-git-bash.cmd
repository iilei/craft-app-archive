@echo off
rem Preflight for the bash-based mise tasks on Windows. Their shell is
rem "bash -c", resolved through PATH; that must be Git Bash. From PowerShell or
rem cmd, "bash" is usually WSL's launcher (System32 or WindowsApps), which runs
rem the scripts in Linux, or fails without an installed distribution.
setlocal
set "kernel="
for /f "delims=" %%i in ('bash -c "uname -s" 2^>nul') do if not defined kernel set "kernel=%%i"
if /i "%kernel:~0,6%"=="MINGW6" exit /b 0
if /i "%kernel:~0,6%"=="MINGW3" exit /b 0
if /i "%kernel:~0,5%"=="MSYS_" exit /b 0

set "found="
for /f "delims=" %%i in ('where bash 2^>nul') do if not defined found set "found=%%i"
if not defined found set "found=none on PATH"
>&2 echo ERROR: these tasks need Git Bash, but "bash" here is not Git Bash.
>&2 echo        bash on PATH: %found%
>&2 echo        Run mise from a Git Bash terminal, or put Git's usr\bin first on PATH,
>&2 echo        e.g. "C:\Program Files\Git\usr\bin". Git for Windows includes Git Bash:
>&2 echo        https://git-scm.com/download/win
exit /b 1
