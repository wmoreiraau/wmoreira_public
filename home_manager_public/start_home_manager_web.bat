@echo off
setlocal

set "PROJECT_DIR=%~dp0"
set "HOST=127.0.0.1"
set "PORT=%~1"

if "%PORT%"=="" set "PORT=8082"

cd /d "%PROJECT_DIR%" || (
  echo Could not open project folder: %PROJECT_DIR%
  exit /b 1
)

echo.
echo Home Manager web launcher
echo Project: %PROJECT_DIR%
echo URL: http://%HOST%:%PORT%
echo.

echo Checking for a running process on port %PORT%...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$port = [int]'%PORT%';" ^
  "$connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue;" ^
  "if (-not $connections) { Write-Host 'Port is free.'; exit 0 }" ^
  "$pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique;" ^
  "foreach ($processId in $pids) {" ^
  "  if ($processId -and $processId -ne $PID) {" ^
  "    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue;" ^
  "    if ($process) { Write-Host ('Stopping ' + $process.ProcessName + ' (PID ' + $processId + ') on port %PORT%...'); Stop-Process -Id $processId -Force }" ^
  "  }" ^
  "}"

if errorlevel 1 (
  echo Failed while checking or stopping the process on port %PORT%.
  exit /b 1
)

echo.
echo Clearing generated Flutter folders that can get locked by OneDrive...
for %%D in (
  "build"
  "ios\Flutter\ephemeral"
  "macos\Flutter\ephemeral"
  "linux\flutter\ephemeral"
  "windows\flutter\ephemeral"
) do (
  if exist "%%~D" (
    attrib -R -S -H "%%~D" /S /D >nul 2>nul
    rmdir /S /Q "%%~D" >nul 2>nul
    if exist "%%~D" (
      echo Could not remove %%~D. Close editors, terminals, or OneDrive sync, then try again.
      exit /b 1
    ) else (
      echo Removed %%~D
    )
  )
)

echo.
if not exist ".dart_tool\package_config.json" (
  echo Flutter package metadata is missing. Running flutter pub get...
  call flutter pub get
  if errorlevel 1 (
    echo flutter pub get failed.
    exit /b 1
  )
) else (
  echo Flutter package metadata already exists. Skipping pub get.
)

echo.
set "DEFINES="
if exist "dart_defines.json" (
  set "DEFINES=--dart-define-from-file=dart_defines.json"
  echo Using Firebase and Worker settings from dart_defines.json.
) else (
  echo dart_defines.json not found - copy dart_defines.example.json and fill it in
  echo to enable sign-in and AI look-ups. Starting without it.
)

echo.
echo Starting Flutter web server...
echo Open http://%HOST%:%PORT% in your browser once Flutter reports it is being served.
echo Press Ctrl+C in this window to stop the server.
echo.

call flutter run -d web-server --no-pub --web-hostname %HOST% --web-port %PORT% %DEFINES%
