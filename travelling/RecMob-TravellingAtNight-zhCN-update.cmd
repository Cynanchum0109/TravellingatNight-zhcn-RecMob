@echo off
setlocal
title Travelling at Night - Chinese Patch Updater
rem Works from anywhere: desktop, downloads folder, or the game root. Fetches
rem the current updater script from the first mirror in BASES that answers,
rem so this file never needs replacing and always runs today's logic; the
rem script finds the game through Steam's own records. If no mirror answers
rem it falls back to the copy the patch installed next to it (only present
rem in the game root).
rem "%~dp0." is this file's folder without the trailing backslash that would
rem otherwise escape the closing quote.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "BASES=https://fastly.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://gcore.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://cdn.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://raw.githubusercontent.com/Cynanchum0109/TravellingatNight-zhcn-RecMob/update/travelling"
set "REMOTE=%TEMP%\travellingzh_updater.ps1"
set "LOCAL=%~dp0BepInEx\plugins\TravellingZh\updater.ps1"

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; foreach ($b in '%BASES%'.Split(' ')) { try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri ($b + '/updater.ps1?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -OutFile '%REMOTE%'; exit 0 } catch { } }; exit 1" >nul 2>&1
if not errorlevel 1 (
  set "SCRIPT=%REMOTE%"
) else if exist "%LOCAL%" (
  echo Could not reach the update server, using the installed updater.
  set "SCRIPT=%LOCAL%"
) else (
  echo Could not reach the update server. Check your network and try again.
  echo.
  pause
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -GameDir "%~dp0."
set "patch_exit=%errorlevel%"
echo.
if not "%patch_exit%"=="0" (
  echo Update did not complete. See the message above.
)
echo.
pause
exit /b %patch_exit%
