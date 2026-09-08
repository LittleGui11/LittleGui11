@echo off
cd /d "%~dp0"
title TaskbarStyleTool
echo Starting...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run.ps1"
if errorlevel 1 pause
