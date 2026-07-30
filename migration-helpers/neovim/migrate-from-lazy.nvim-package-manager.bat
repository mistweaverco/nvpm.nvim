@echo off
REM Migrate plugins from lazy.nvim's lazy-lock.json into nvpm (pinned commits).
REM Uses Windows built-in PowerShell 5.1 (ConvertFrom-Json) - no Python required.
REM
REM Examples:
REM   migrate-from-lazy.nvim-package-manager.bat -DryRun
REM   migrate-from-lazy.nvim-package-manager.bat -Lockfile C:\path\lazy-lock.json
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%migrate-from-lazy.nvim-package-manager.ps1"

if not exist "%PS1%" (
  echo error: missing "%PS1%" 1>&2
  exit /b 1
)

REM Prefer Windows PowerShell 5.1 from System32 (ships with Windows 10 / 11).
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" (
  set "POWERSHELL=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
)
if not exist "%POWERSHELL%" (
  where pwsh >nul 2>&1
  if not errorlevel 1 (
    for /f "delims=" %%P in ('where pwsh') do (
      set "POWERSHELL=%%P"
      goto :run
    )
  )
)
if not exist "%POWERSHELL%" (
  where powershell >nul 2>&1
  if not errorlevel 1 (
    for /f "delims=" %%P in ('where powershell') do (
      set "POWERSHELL=%%P"
      goto :run
    )
  )
)
if not exist "%POWERSHELL%" (
  echo error: Windows PowerShell not found. 1>&2
  echo hint: PowerShell 5.1 ships with Windows 10+ at: 1>&2
  echo       %%SystemRoot%%\System32\WindowsPowerShell\v1.0\powershell.exe 1>&2
  exit /b 1
)

:run
REM Bypass execution policy for this process only. JSON parsing uses ConvertFrom-Json.
"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
