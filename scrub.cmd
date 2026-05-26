@echo off
powershell.exe -NoLogo -ExecutionPolicy RemoteSigned -File "C:\DEV\scrub\Run-Scrub.ps1" %*
