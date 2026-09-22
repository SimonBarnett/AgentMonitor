@echo off
setlocal
if "%~1"=="" (
    echo Usage: %~nx0 grok ^| cursor [new]
    echo   resume: %~nx0 cursor
    echo   new:      %~nx0 cursor new
    exit /b 1
)
set "KIND=%~1"
set "MODE=%~2"
set "PSARGS=-WatchWorker"
if /i "%KIND%"=="cursor" set "PSARGS=%PSARGS% -Cursor"
if /i "%KIND%"=="grok" set "PSARGS=%PSARGS% -Grok"
if /i not "%KIND%"=="cursor" if /i not "%KIND%"=="grok" (
    echo Unknown kind "%KIND%" - use grok or cursor
    exit /b 1
)
if /i "%MODE%"=="new" set "PSARGS=%PSARGS% -New"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Watch-AgentHealth.ps1" %PSARGS%
echo Watch monitor started (hidden). Opens agent TUI. Log: %USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log
exit /b 0
