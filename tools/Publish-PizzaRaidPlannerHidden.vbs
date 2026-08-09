Option Explicit

Dim shell
Dim scriptPath
Dim command
Dim exitCode

Set shell = CreateObject("WScript.Shell")
scriptPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\PizzaRaidPlanner\bin\Sync-PizzaRaidPlannerToSheets.ps1")
command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -Publish"
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
