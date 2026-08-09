Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\tools\Sync-PizzaRaidPlannerToSheets.ps1"

$bpc = New-Object 'System.Collections.Generic.List[string]'
$bpc.Add("H1`tTester`tM1`tMelee`tR1`tRanged`t`tVALANAR ACTIVE / EMPOWERED SHOCK VORTEX")
while ($bpc.Count -lt 53) { $bpc.Add('') }

$bql = New-Object 'System.Collections.Generic.List[string]'
$bql.Add("Initial`t`t`t`tFirst -> Second`t`t`t`t`t`t`t`t`t`t`t`t`t`tCOPY A55:Q62")
while ($bql.Count -lt 10) { $bql.Add('') }
$bql[9] = "H1`tHealer`t`tR1`tRanged`t`tL1`tMelee`t`tCOPY A64:H73"
while ($bql.Count -lt 22) { $bql.Add('') }
$bql[21] = "1st`tPaladin`t`tShadow AM`t1st`t`tPaladin`t`tCOPY A76:G79"

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
