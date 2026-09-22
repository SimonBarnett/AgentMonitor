@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Watch-AgentHealth.ps1" -WatchWorker -Grok
