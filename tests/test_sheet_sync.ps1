Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  $env:LOCALAPPDATA = [IO.Path]::GetTempPath()
}
. "$PSScriptRoot\..\tools\Sync-PizzaRaidPlannerToSheets.ps1"

$bpc = New-Object 'System.Collections.Generic.List[string]'
$bpc.Add("H1`tTester`tM1`tMelee`tR1`tRanged`t`tVALANAR ACTIVE / EMPOWERED SHOCK VORTEX")
while ($bpc.Count -lt 53) { $bpc.Add('') }

$bql = New-Object 'System.Collections.Generic.List[string]'
$bql.Add("Initial`t`t`t`tFirst -> Second`t`t`t`t`t`t`t`t`t`t`t`t`t`tCOPY A55:Q62")
while ($bql.Count -lt 10) { $bql.Add('') }
$bql[9] = "H1`tHealer`t`tR1`tRanged`t`tL1`tMelee`t`tCOPY A64:H73"
while ($bql.Count -lt 22) { $bql.Add('') }
$bql[21] = "1st`tAzyia`t`tAM`t1st / 2nd`t`tAzyia / Pasyon`t`tCOPY A76:G79"

$combined = Merge-PizzaRaidPlannerTsv -BpcTsv ([string]::Join("`r`n", $bpc)) -BqlTsv ([string]::Join("`r`n", $bql))
$lines = @(Get-TsvLines -Value $combined)
if ($lines.Count -ne 76) { throw "Expected 76 combined rows, found $($lines.Count)." }
if ($lines[53] -ne '') { throw 'Row 54 must remain the single blank spacer.' }
if (-not $lines[54].Contains('COPY A55:Q62')) { throw 'BQL bites must begin at row 55.' }
if (-not $lines[63].Contains('COPY A64:H73')) { throw 'BQL groups must begin at row 64.' }
if (-not $lines[75].Contains('COPY A76:G79')) { throw 'BQL cooldowns must begin at row 76.' }

$overlap = [string]::Join("`r`n", @($bpc) + @('WARNING'))
$blocked = $false
try { Merge-PizzaRaidPlannerTsv -BpcTsv $overlap -BqlTsv ([string]::Join("`r`n", $bql)) | Out-Null }
catch { $blocked = $_.Exception.Message.Contains('would overlap') }
if (-not $blocked) { throw 'BPC rows beyond 53 must block the sync.' }

if ((Get-PizzaRaidPlannerDesktopAction) -ne 'replaceWoWTsvDump') {
  throw 'The default desktop action must remain sync-only.'
}
if ((Get-PizzaRaidPlannerDesktopAction -PublishToDiscord) -ne 'prepareRaidPlan') {
  throw 'The publish desktop action must begin the authenticated 4K transaction.'
}

function New-TestBundleSavedVariables {
  param([hashtable]$Metadata)
  $json = $Metadata | ConvertTo-Json -Compress
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
  return 'PizzaRaidPlannerDB = { ["bundleMetaB64"] = "' + $encoded + '" }'
}

$bundleSavedVariables = New-TestBundleSavedVariables -Metadata @{
  bundleId = 'bundle-2'
  sourceId = 'festergut-2'
  revision = 2
  rosterHash = 'roster-abc'
  bpcBundleId = 'bundle-2'
  bqlBundleId = 'bundle-2'
  dirty = $false
}
$bundleMetadata = Get-PizzaRaidPlannerBundleMetadata -SavedVariablesText $bundleSavedVariables
if ($bundleMetadata.bundleId -ne 'bundle-2' -or [int]$bundleMetadata.revision -ne 2) {
  throw 'Atomic plan-bundle metadata did not round-trip from SavedVariables.'
}

$dirtyBundleBlocked = $false
try {
  Get-PizzaRaidPlannerBundleMetadata -SavedVariablesText (New-TestBundleSavedVariables -Metadata @{
    bundleId = 'bundle-3'; sourceId = 'festergut-3'; revision = 3; rosterHash = 'roster-def'
    bpcBundleId = 'bundle-3'; bqlBundleId = 'bundle-3'; dirty = $true; dirtyReason = 'roster'
  }) | Out-Null
} catch { $dirtyBundleBlocked = $_.Exception.Message.Contains('roster changed') }
if (-not $dirtyBundleBlocked) { throw 'A dirty roster plan must be blocked before sheet or Discord publication.' }

$mixedBundleBlocked = $false
try {
  Get-PizzaRaidPlannerBundleMetadata -SavedVariablesText (New-TestBundleSavedVariables -Metadata @{
    bundleId = 'bundle-4'; sourceId = 'festergut-4'; revision = 4; rosterHash = 'roster-ghi'
    bpcBundleId = 'bundle-4'; bqlBundleId = 'bundle-old'; dirty = $false
  }) | Out-Null
} catch { $mixedBundleBlocked = $_.Exception.Message.Contains('different plan revisions') }
if (-not $mixedBundleBlocked) { throw 'Mixed BPC/BQL plan revisions must be blocked before publication.' }

$invalidRevisionBlocked = $false
try {
  Get-PizzaRaidPlannerBundleMetadata -SavedVariablesText (New-TestBundleSavedVariables -Metadata @{
    bundleId = 'bundle-zero'; sourceId = 'festergut-zero'; revision = 0; rosterHash = 'roster-jkl'
    bpcBundleId = 'bundle-zero'; bqlBundleId = 'bundle-zero'; dirty = $false
  }) | Out-Null
} catch { $invalidRevisionBlocked = $_.Exception.Message.Contains('invalid revision') }
if (-not $invalidRevisionBlocked) { throw 'A zero plan revision must be blocked before publication.' }

$missingBenchmarkBlocked = $false
try {
  Get-PizzaRaidPlannerBundleMetadata -SavedVariablesText (New-TestBundleSavedVariables -Metadata @{
    bundleId = 'bundle-no-source'; revision = 5; rosterHash = 'roster-mno'
    bpcBundleId = 'bundle-no-source'; bqlBundleId = 'bundle-no-source'; dirty = $false
  }) | Out-Null
} catch { $missingBenchmarkBlocked = $_.Exception.Message.Contains('no confirmed Festergut benchmark') }
if (-not $missingBenchmarkBlocked) { throw 'A plan without a confirmed Festergut source must be blocked before publication.' }

$pngBytes = New-Object byte[] 24
[byte[]]$signature = 137, 80, 78, 71, 13, 10, 26, 10
[Array]::Copy($signature, 0, $pngBytes, 0, $signature.Length)
$pngBytes[16] = 0; $pngBytes[17] = 0; $pngBytes[18] = 16; $pngBytes[19] = 0
$pngBytes[20] = 0; $pngBytes[21] = 0; $pngBytes[22] = 7; $pngBytes[23] = 3
$metadata = Get-PngMetadataFromBytes -Bytes $pngBytes
if ($metadata.Width -ne 4096 -or $metadata.Height -ne 1795) {
  throw "PNG metadata parsing failed: $($metadata.Width)x$($metadata.Height)."
}
Assert-RaidPngMetadata -Metadata $metadata -ExpectedWidth 4096 -ExpectedHeight 1795 | Out-Null

$lowResolutionBlocked = $false
try { Assert-RaidPngMetadata -Metadata ([pscustomobject]@{ Width = 1024; Height = 448; Bytes = 500000 }) -ExpectedWidth 4096 -ExpectedHeight 1795 | Out-Null }
catch { $lowResolutionBlocked = $_.Exception.Message.Contains('native 4096px') }
if (-not $lowResolutionBlocked) { throw 'The desktop publisher must reject the old 1024px thumbnails.' }

if ($env:OS -eq 'Windows_NT') {
  Add-Type -AssemblyName System.Drawing
  $marginTestPath = Join-Path ([IO.Path]::GetTempPath()) ('PizzaRaidPlanner-margin-' + [guid]::NewGuid().ToString('N') + '.png')
  $marginBitmap = New-Object Drawing.Bitmap(40, 30, ([Drawing.Imaging.PixelFormat]::Format32bppArgb))
  $marginGraphics = [Drawing.Graphics]::FromImage($marginBitmap)
  try {
    $marginGraphics.Clear([Drawing.Color]::White)
    $marginGraphics.FillRectangle([Drawing.Brushes]::Navy, 2, 3, 34, 22)
    $marginBitmap.Save($marginTestPath, [Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $marginGraphics.Dispose()
    $marginBitmap.Dispose()
  }

  try {
    $cleaned = Convert-RaidPngOuterWhitespaceToTransparency -Path $marginTestPath -MaximumMarginPixels 10
    if (
      $cleaned.Width -ne 40 -or
      $cleaned.Height -ne 30 -or
      $cleaned.TransparentLeft -ne 2 -or
      $cleaned.TransparentTop -ne 3 -or
      $cleaned.TransparentRight -ne 4 -or
      $cleaned.TransparentBottom -ne 5
    ) {
      throw 'Outer-whitespace cleanup changed dimensions or detected the wrong margins.'
    }

    $verifiedBitmap = [Drawing.Bitmap]::FromFile($marginTestPath)
    try {
      if ($verifiedBitmap.GetPixel(0, 0).A -ne 0 -or $verifiedBitmap.GetPixel(39, 29).A -ne 0) {
        throw 'Outer-whitespace cleanup did not make the image edges transparent.'
      }
      $contentPixel = $verifiedBitmap.GetPixel(2, 3)
      if ($contentPixel.A -ne 255 -or $contentPixel.B -lt 100) {
        throw 'Outer-whitespace cleanup altered visible raid-plan pixels.'
      }
    } finally {
      $verifiedBitmap.Dispose()
    }
  } finally {
    if (Test-Path -LiteralPath $marginTestPath) { Remove-Item -LiteralPath $marginTestPath -Force }
  }
} else {
  Write-Output 'Outer-whitespace image test: SKIP (the production renderer is Windows-only).'
}

$originalLastErrorPath = $script:LastErrorPath
$testErrorPath = Join-Path ([IO.Path]::GetTempPath()) ('PizzaRaidPlanner-error-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  $script:LastErrorPath = $testErrorPath
  try { throw 'Visible launcher failure' }
  catch { Write-SyncFailureLog -ErrorRecord $_ }
  $loggedFailure = Get-Content -LiteralPath $testErrorPath -Raw | ConvertFrom-Json
  if ($loggedFailure.Message -ne 'Visible launcher failure' -or -not $loggedFailure.FailedAt) {
    throw 'The launcher failure log did not preserve the visible error details.'
  }
} finally {
  $script:LastErrorPath = $originalLastErrorPath
  if (Test-Path -LiteralPath $testErrorPath) { Remove-Item -LiteralPath $testErrorPath -Force }
}

Write-Output 'test_sheet_sync: PASS'
