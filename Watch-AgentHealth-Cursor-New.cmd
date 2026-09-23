@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Watch-AgentHealth.ps1" -WatchWorker -Cursor -New
