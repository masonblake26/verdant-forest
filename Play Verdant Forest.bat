@echo off
rem Runs Verdant Forest from source with Godot 4.7. Set GODOT to the full path of your Godot 4.7 executable,
rem or put Godot on your PATH as godot.exe. (The ready-made build in Releases needs none of this.)
if "%GODOT%"=="" set "GODOT=godot"
start "" "%GODOT%" --path "%~dp0."
