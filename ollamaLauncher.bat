@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\OllamaLauncher.ps1" %*
exit /b %errorlevel%
