@echo off
rem Runs seed.ps1 bypassing the default execution policy. Works from any folder.
rem Usage: backend\seed.cmd [-Reset] [-All]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0seed.ps1" %*
