<#
Extracts PizzaRaidPlanner's Base64 export fields without evaluating SavedVariables Lua.
The game writes SavedVariables only on /reload, logout, or exit.
#>
[CmdletBinding()]
param(
  [string]$WowPath,
  [string]$SavedVariablesPath,
  [string]$OutputDirectory = (Join-Path $PSScriptRoot 'exports'),
  [switch]$Watch
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SavedVariablesPath {
  if ($SavedVariablesPath) { return (Resolve-Path -LiteralPath $SavedVariablesPath).Path }
  if (-not $WowPath) { throw 'Supply -SavedVariablesPath or -WowPath.' }
  $candidate = Join-Path $WowPath 'WTF\Account'
  if (-not (Test-Path -LiteralPath $candidate)) { throw "No WTF\Account directory under $WowPath." }
  $matches = Get-ChildItem -LiteralPath $candidate -Directory | ForEach-Object { Join-Path $_.FullName 'SavedVariables\PizzaRaidPlanner.lua' } | Where-Object { Test-Path -LiteralPath $_ }
  if (@($matches).Count -ne 1) { throw 'Found zero or multiple PizzaRaidPlanner.lua files. Supply -SavedVariablesPath explicitly.' }
  return $matches[0]
}
function Get-Payload([string]$Text, [string]$Name) {
  # Deliberately narrow: accept only an assigned quoted Base64 field, never Lua expressions.
  $pattern = '(?m)(?:\["' + [regex]::Escape($Name) + '"\]|\b' + [regex]::Escape($Name) + '\b)\s*=\s*"([A-Za-z0-9+/=]+)"'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Missing or invalid $Name field." }
  try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups[1].Value)) }
  catch { throw "Invalid Base64 payload in $Name." }
}
function Export-Latest {
  $path = Resolve-SavedVariablesPath
  $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'latest-bite-plan.tsv'), (Get-Payload $raw 'planTSVB64'), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'latest-roster.tsv'), (Get-Payload $raw 'rosterTSVB64'), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'latest-bpc-positions.tsv'), (Get-Payload $raw 'bpcTSVB64'), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'latest-bite-plan.json'), (Get-Payload $raw 'jsonB64'), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $OutputDirectory 'latest-discord.txt'), (Get-Payload $raw 'discordB64'), [Text.UTF8Encoding]::new($false))
  Write-Host "Exported PizzaRaidPlanner payload written after $(Get-Item -LiteralPath $path | Select-Object -ExpandProperty LastWriteTime)."
}
if ($Watch) {
  Write-Host 'Watching SavedVariables. Use /reload, logout, or exit WoW to flush a new export. Ctrl+C stops watching.'
  $last = [datetime]::MinValue
  while ($true) { $path=Resolve-SavedVariablesPath; $stamp=(Get-Item -LiteralPath $path).LastWriteTimeUtc; if ($stamp -gt $last) { Start-Sleep -Milliseconds 400; Export-Latest; $last=$stamp }; Start-Sleep -Seconds 2 }
} else { Export-Latest }
