@echo off
powershell.exe -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0Install-Scrub.ps1" %*
pause
