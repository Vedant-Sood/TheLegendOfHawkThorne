@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem GODOT is an executable path; quote it here rather than in the variable value.
if defined GODOT goto from_variable
for %%G in (godot.exe godot4.exe) do (
  for %%P in ("%%~$PATH:G") do (
    if not "%%~P"=="" (
      set "HAWK_ENGINE=%%~P"
      goto engine_found
    )
  )
)
echo Godot 4.3 is required. Set GODOT to the standard edition executable or add godot.exe/godot4.exe to PATH. 1>&2
exit /b 127

:from_variable
set "HAWK_ENGINE=%GODOT%"
if exist "%HAWK_ENGINE%" goto engine_found
for %%G in ("%GODOT%") do (
  for %%P in ("%%~$PATH:G") do (
    if not "%%~P"=="" set "HAWK_ENGINE=%%~P"
  )
)

:engine_found
if not exist "%HAWK_ENGINE%" (
  echo Godot executable not found: %HAWK_ENGINE% 1>&2
  exit /b 127
)
rem CALL is deliberately avoided: it would re-expand command-line arguments.
"%HAWK_ENGINE%" --path "%~dp0." %*
exit /b %ERRORLEVEL%
