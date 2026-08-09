[CmdletBinding()]
param(
  [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path
$excludedDirectories = @('.git', 'dist')
$binaryExtensions = @('.gif', '.ico', '.jpg', '.jpeg', '.png', '.tga', '.webp', '.zip')

$secretPatterns = [ordered]@{
  'Discord webhook credential' = 'https://discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9._-]{20,}'
  'Apps Script deployment credential' = 'https://script\.google\.com/macros/s/[A-Za-z0-9_-]{20,}/exec'
  'GitHub token' = '(?i)\b(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}'
  'Google API key' = '\bAIza[A-Za-z0-9_-]{30,}'
  'Slack-style token' = '\bxox[baprs]-[A-Za-z0-9-]{20,}'
  'Private key' = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'Fixed workbook identifier' = '(?i)(?:spreadsheet|workbook)(?:[_-]?id)?\s*[:=]\s*["''][A-Za-z0-9_-]{25,}["'']'
  'Personal Windows user path' = '(?i)[A-Z]:\\Users\\(?!YOUR_USER(?:\\|\b))[^\\\r\n]+\\'
  'Personal WoW account path' = '(?i)WTF\\Account\\(?!YOUR_ACCOUNT(?:\\|\b))[^\\\r\n]+\\SavedVariables'
}

$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
  $relative = $_.FullName.Substring($root.Length + 1)
  $segments = $relative -split '[\\/]'
  -not ($segments | Where-Object { $_ -in $excludedDirectories }) -and
  $_.Extension.ToLowerInvariant() -notin $binaryExtensions
}

$findings = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $files) {
  $text = [IO.File]::ReadAllText($file.FullName)
  $relative = $file.FullName.Substring($root.Length + 1)

  foreach ($entry in $secretPatterns.GetEnumerator()) {
    if ([regex]::IsMatch($text, $entry.Value)) {
      $findings.Add([pscustomobject]@{ File = $relative; Category = $entry.Key })
    }
  }
}

$forbiddenFiles = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
  $_.Name -in @('SheetSync.json', 'last-error.log', 'last-sync.json', 'last-upload.tsv')
}
foreach ($file in $forbiddenFiles) {
  $findings.Add([pscustomobject]@{
    File = $file.FullName.Substring($root.Length + 1)
    Category = 'Local publisher state file'
  })
}

if ($findings.Count -gt 0) {
  $findings | Sort-Object File, Category | Format-Table -AutoSize | Out-String | Write-Host
  throw "Public repository secret gate failed with $($findings.Count) finding(s). Values were intentionally redacted."
}

$appsScript = [IO.File]::ReadAllText((Join-Path $root 'tools\DiscordPost.gs'))
if ($appsScript -match 'const\s+RAID_SPREADSHEET_ID\s*=') {
  throw 'Apps Script must bind a workbook at setup time; a fixed spreadsheet ID is forbidden.'
}
if ($appsScript -notmatch 'RAID_SPREADSHEET_ID_PROPERTY') {
  throw 'Apps Script is missing the per-workbook binding property.'
}

Write-Output "Public repository secret gate: PASS ($($files.Count) text files scanned; no secret values printed)."
