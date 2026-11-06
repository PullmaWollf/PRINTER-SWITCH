@echo off
title PRINTER SWITCH 4.1

start "" powershell.exe ^
-WindowStyle Hidden ^
-NoLogo ^
-NoProfile ^
-STA ^
-ExecutionPolicy Bypass ^
-File "%~dp0PRINTER_SWITCH.ps1"

exit /b
