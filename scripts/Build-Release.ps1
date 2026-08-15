[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $scriptRoot }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $RepositoryRoot 'dist' }
$root = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path
$tocPath = Join-Path $root 'PizzaRaidPlanner.toc'
$toc = [IO.File]::ReadAllText($tocPath)
$versionMatch = [regex]::Match($toc, '(?m)^## Version:\s*(\S+)\s*$')
if (-not $versionMatch.Success) { throw 'PizzaRaidPlanner.toc does not declare a version.' }
$version = $versionMatch.Groups[1].Value

& (Join-Path $root 'scripts\Test-PublicRepository.ps1') -RepositoryRoot $root

$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('PizzaRaidPlanner-release-' + [guid]::NewGuid().ToString('N'))
$addonStage = Join-Path $stageRoot 'addon\PizzaRaidPlanner'
$desktopStage = Join-Path $stageRoot 'desktop\PizzaRaidPlanner-Desktop'

$runtimeFiles = @(
  'BPC.lua', 'BQL.lua', 'Commands.lua', 'Constants.lua', 'Core.lua', 'Damage.lua',
  'Database.lua', 'Encounter.lua', 'Export.lua', 'ICCSession.lua', 'Optimizer.lua',
  'PizzaRaidPlanner.toc', 'PlanBundle.lua', 'Roles.lua', 'Roster.lua', 'Segments.lua', 'SkadaAdapter.lua', 'UI.lua'
)
$desktopFiles = @(
  'DiscordPost.gs', 'Export-PizzaRaidPlanner.ps1', 'Publish-PizzaRaidPlannerHidden.vbs',
  'PizzaWarriorsSheetSync.ico', 'README.md', 'Sync-PizzaRaidPlannerToSheets.ps1'
)

try {
  New-Item -ItemType Directory -Path (Join-Path $addonStage 'Media') -Force | Out-Null
  New-Item -ItemType Directory -Path $desktopStage -Force | Out-Null

  foreach ($relative in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination (Join-Path $addonStage $relative)
  }
  Copy-Item -LiteralPath (Join-Path $root 'Media\PizzaWarriorsLogo.tga') -Destination (Join-Path $addonStage 'Media\PizzaWarriorsLogo.tga')
  Copy-Item -LiteralPath (Join-Path $root 'LICENSE.md') -Destination (Join-Path $addonStage 'LICENSE.md')
  Copy-Item -LiteralPath (Join-Path $root 'NOTICE.md') -Destination (Join-Path $addonStage 'NOTICE.md')

  foreach ($relative in $desktopFiles) {
    Copy-Item -LiteralPath (Join-Path $root ('tools\' + $relative)) -Destination (Join-Path $desktopStage $relative)
  }
  Copy-Item -LiteralPath (Join-Path $root 'LICENSE.md') -Destination (Join-Path $desktopStage 'LICENSE.md')
  Copy-Item -LiteralPath (Join-Path $root 'NOTICE.md') -Destination (Join-Path $desktopStage 'NOTICE.md')
  Copy-Item -LiteralPath (Join-Path $root 'docs\ADAPTATION_GUIDE.md') -Destination (Join-Path $desktopStage 'ADAPTATION_GUIDE.md')

  $addonArchive = Join-Path $output ("PizzaRaidPlanner-Addon-$version.zip")
  $desktopArchive = Join-Path $output ("PizzaRaidPlanner-Desktop-$version.zip")
  if (Test-Path -LiteralPath $addonArchive) { [IO.File]::Delete($addonArchive) }
  if (Test-Path -LiteralPath $desktopArchive) { [IO.File]::Delete($desktopArchive) }

  Compress-Archive -LiteralPath $addonStage -DestinationPath $addonArchive -CompressionLevel Optimal
  Compress-Archive -LiteralPath $desktopStage -DestinationPath $desktopArchive -CompressionLevel Optimal

  $artifacts = @($addonArchive, $desktopArchive)
  $checksumLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($artifact))"
  }
  [IO.File]::WriteAllLines(
    (Join-Path $output 'SHA256SUMS.txt'),
    $checksumLines,
    [Text.UTF8Encoding]::new($false)
  )
} finally {
  if (Test-Path -LiteralPath $stageRoot -PathType Container) {
    $resolvedStage = (Resolve-Path -LiteralPath $stageRoot).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
      [IO.Path]::DirectorySeparatorChar,
      [IO.Path]::AltDirectorySeparatorChar
    )
    $tempPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar + 'PizzaRaidPlanner-release-'
    if (-not $resolvedStage.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove unexpected staging directory: $resolvedStage"
    }
    [IO.Directory]::Delete($resolvedStage, $true)
  }
}

Get-ChildItem -LiteralPath $output -File | Sort-Object Name | Select-Object Name, Length
