@echo off
powershell.exe -NoLogo -ExecutionPolicy RemoteSigned -File "%~dp0Run-Scrub.ps1" %*
