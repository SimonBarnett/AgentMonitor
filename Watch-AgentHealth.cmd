@echo off
setlocal
if "%~1"=="" (
    echo Usage: %~nx0 grok ^| cursor [new] [on ^| off]
    echo   resume: %~nx0 cursor
    echo   new:      %~nx0 cursor new
    echo   hidden:   %~nx0 cursor off
    echo   on/off may appear in either order with new (default on).
    exit /b 1
)
set "KIND=%~1"
set "WINMODE=on"
set "PSARGS=-WatchWorker"
if /i "%KIND%"=="cursor" set "PSARGS=%PSARGS% -Cursor"
if /i "%KIND%"=="grok" set "PSARGS=%PSARGS% -Grok"
if /i not "%KIND%"=="cursor" if /i not "%KIND%"=="grok" (
    echo Unknown kind "%KIND%" - use grok or cursor
    exit /b 1
)
if /i "%~2"=="new" set "PSARGS=%PSARGS% -New"
if /i "%~2"=="on" set "WINMODE=on"
if /i "%~2"=="off" set "WINMODE=off"
if /i "%~3"=="new" set "PSARGS=%PSARGS% -New"
if /i "%~3"=="on" set "WINMODE=on"
if /i "%~3"=="off" set "WINMODE=off"
set "PSARGS=%PSARGS% -Windows %WINMODE%"
if /i "%WINMODE%"=="off" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Watch-AgentHealth.ps1" %PSARGS%
    echo Watch monitor started hidden (-Windows off). Log: %USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Watch-AgentHealth.ps1" %PSARGS%
exit /b 0
