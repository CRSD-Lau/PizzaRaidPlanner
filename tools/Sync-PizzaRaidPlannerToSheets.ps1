<#
Reads PizzaRaidPlanner's Base64 TSV exports without evaluating SavedVariables
Lua, combines BPC at row 1 with BQL at row 55, and sends authenticated bounded
updates to the bound Google Apps Script web app. Publish mode receives cropped
vector PDFs, renders native 4096px PNGs with Windows' built-in PDF engine, and
returns those exact files for the server-side Discord webhook.

WoW flushes SavedVariables only on /reload, logout, or exit. The normal raid
flow is therefore: select/confirm the Festergut source, /reload, double-click
the desktop shortcut.
#>
[CmdletBinding()]
param(
  [string]$SavedVariablesPath,
  [switch]$Configure,
  [switch]$AllowStale,
  [ValidateRange(1, 240)][int]$MaximumAgeMinutes = 20,
  [switch]$Publish,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:DefaultSavedVariablesPath = ''
$script:ConfigDirectory = Join-Path $env:LOCALAPPDATA 'PizzaRaidPlanner'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'SheetSync.json'
$script:LastUploadPath = Join-Path $script:ConfigDirectory 'last-upload.tsv'
$script:LastSyncPath = Join-Path $script:ConfigDirectory 'last-sync.json'
$script:LastErrorPath = Join-Path $script:ConfigDirectory 'last-error.log'
$script:BpcLastRow = 53
$script:BqlStartRow = 55
$script:PublishProtocolVersion = 2
$script:RaidPngTargetWidth = 4096
$script:DiscordMaxAttachmentBytes = 10MB
$script:WinRtPdfRendererInitialized = $false

function Show-SyncMessage {
  param([string]$Text, [string]$Title = 'Pizza Warriors Sheet Sync', [string]$Icon = 'Information')
  Add-Type -AssemblyName System.Windows.Forms
  $iconValue = [System.Windows.Forms.MessageBoxIcon][Enum]::Parse([System.Windows.Forms.MessageBoxIcon], $Icon, $true)
  [void][System.Windows.Forms.MessageBox]::Show(
    $Text,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $iconValue
  )
}

function Write-SyncFailureLog {
  param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

  New-Item -ItemType Directory -Path $script:ConfigDirectory -Force | Out-Null
  $innerMessage = if ($ErrorRecord.Exception.InnerException) {
    $ErrorRecord.Exception.InnerException.Message
  } else {
    ''
  }
  $details = [ordered]@{
    FailedAt = (Get-Date).ToString('o')
    Message = $ErrorRecord.Exception.Message
    ExceptionType = $ErrorRecord.Exception.GetType().FullName
    InnerMessage = $innerMessage
    ScriptStackTrace = [string]$ErrorRecord.ScriptStackTrace
  }
  [IO.File]::WriteAllText(
    $script:LastErrorPath,
    ($details | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false)
  )
}

function Read-SyncInput {
  param([string]$Prompt, [string]$Title, [string]$Default = '')
  Add-Type -AssemblyName Microsoft.VisualBasic
  return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default).Trim()
}

function Protect-SyncToken {
  param([Parameter(Mandatory)][string]$Token)
  $secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
  return ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-SyncToken {
  param([Parameter(Mandatory)][string]$EncryptedToken)
  $secure = ConvertTo-SecureString -String $EncryptedToken
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-SheetSyncConfig {
  param([switch]$ForceConfigure, [string]$PreferredSavedVariablesPath)

  $existing = $null
  if (Test-Path -LiteralPath $script:ConfigPath) {
    $existing = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
  }

  if (-not $ForceConfigure -and $existing) { return $existing }

  $defaultEndpoint = if ($existing -and $existing.Endpoint) { [string]$existing.Endpoint } else { '' }
  $endpoint = Read-SyncInput -Title 'Pizza Warriors Sheet Sync' -Prompt 'Paste the Web app URL from Raid Positions > Configure desktop TSV sync.' -Default $defaultEndpoint
  if (-not $endpoint) { throw 'Desktop sync setup was cancelled.' }
  if ($endpoint -notmatch '^https://script\.google\.com/macros/s/[^/]+/exec$') {
    throw 'The Web app URL must look like https://script.google.com/macros/s/.../exec.'
  }

  $token = Read-SyncInput -Title 'Pizza Warriors Sheet Sync' -Prompt 'Paste the private upload token from the same setup dialog.'
  if ($token.Length -lt 32) { throw 'The private upload token is missing or too short.' }

  $defaultSavedVariables = if ($PreferredSavedVariablesPath) {
    $PreferredSavedVariablesPath
  } elseif ($existing -and $existing.SavedVariablesPath) {
    [string]$existing.SavedVariablesPath
  } else {
    $script:DefaultSavedVariablesPath
  }
  $sourcePath = Read-SyncInput -Title 'Pizza Warriors Sheet Sync' -Prompt 'Select your WoW account''s PizzaRaidPlanner SavedVariables file.' -Default $defaultSavedVariables
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'PizzaRaidPlanner.lua was not found at the selected path.' }

  $config = [ordered]@{
    Endpoint = $endpoint
    EncryptedToken = Protect-SyncToken -Token $token
    SavedVariablesPath = (Resolve-Path -LiteralPath $sourcePath).Path
    Workbook = 'Icecrown Raid Positions Template'
    Sheet = 'WoW TSV Dump'
  }

  New-Item -ItemType Directory -Path $script:ConfigDirectory -Force | Out-Null
  [IO.File]::WriteAllText(
    $script:ConfigPath,
    ($config | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false)
  )
  return [pscustomobject]$config
}

function Get-Base64ExportPayload {
  param([Parameter(Mandatory)][string]$SavedVariablesText, [Parameter(Mandatory)][string]$Name)
  # Deliberately narrow: accept only an assigned quoted Base64 field. Never
  # execute or import SavedVariables Lua.
  $pattern = '(?m)(?:\["' + [regex]::Escape($Name) + '"\]|\b' + [regex]::Escape($Name) + '\b)\s*=\s*"([A-Za-z0-9+/=]+)"'
  $match = [regex]::Match($SavedVariablesText, $pattern)
  if (-not $match.Success) { throw "Missing or invalid $Name field. Type /reload in WoW, then try again." }
  try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups[1].Value)) }
  catch { throw "Invalid Base64 payload in $Name." }
}

function Get-TsvLines {
  param([Parameter(Mandatory)][string]$Value)
  $normalized = $Value.Replace("`r`n", "`n").Replace("`r", "`n")
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in $normalized.Split([char]10)) { $lines.Add($line) }
  while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
  return $lines.ToArray()
}

function Merge-PizzaRaidPlannerTsv {
  param([Parameter(Mandatory)][string]$BpcTsv, [Parameter(Mandatory)][string]$BqlTsv)
  $bpc = @(Get-TsvLines -Value $BpcTsv)
  $bql = @(Get-TsvLines -Value $BqlTsv)

  if ($bpc.Count -gt $script:BpcLastRow) {
    throw "BPC produced $($bpc.Count) rows and would overlap the fixed BQL row-55 anchor. Resolve the BPC warning rows in-game before syncing."
  }
  if ($BpcTsv.IndexOf('VALANAR ACTIVE / EMPOWERED SHOCK VORTEX', [StringComparison]::Ordinal) -lt 0) {
    throw 'The BPC TSV marker is missing.'
  }
  foreach ($marker in @('COPY A55:Q62', 'COPY A64:H73', 'COPY A76:G79')) {
    if ($BqlTsv.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
      throw "The BQL TSV is from an older addon build or is incomplete ($marker missing). Type /reload after installing version 1.0.1."
    }
  }

  $combined = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in $bpc) { $combined.Add($line) }
  while ($combined.Count -lt ($script:BqlStartRow - 1)) { $combined.Add('') }
  foreach ($line in $bql) { $combined.Add($line) }

  if ($combined[0].Split("`t")[0] -ne 'H1') { throw 'BPC is not anchored at A1.' }
  if ($combined[$script:BqlStartRow - 1].Split("`t").Count -lt 1) { throw 'BQL row-55 anchor is missing.' }
  return [string]::Join("`r`n", $combined)
}

function Get-PizzaRaidPlannerDesktopAction {
  param([switch]$PublishToDiscord)
  if ($PublishToDiscord) { return 'prepareRaidPlan' }
  return 'replaceWoWTsvDump'
}

function Invoke-PizzaRaidPlannerEndpoint {
  param(
    [Parameter(Mandatory)][string]$Endpoint,
    [Parameter(Mandatory)][hashtable]$Payload,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 60
  )

  $json = $Payload | ConvertTo-Json -Depth 8 -Compress
  $request = @{
    Uri = $Endpoint
    Method = 'Post'
    ContentType = 'application/json; charset=utf-8'
    Body = [Text.Encoding]::UTF8.GetBytes($json)
    TimeoutSec = $TimeoutSeconds
  }
  $response = Invoke-RestMethod @request

  if (-not $response -or $response.ok -ne $true) {
    $message = if ($response -and $response.error) { [string]$response.error } else { 'No valid response from Google Apps Script.' }
    if ($Payload.action -eq 'prepareRaidPlan' -and $message -match 'Unsupported desktop TSV action') {
      throw 'The Google Apps Script deployment is still using the old publisher. Replace it with the current DiscordPost.gs, then update the existing web-app deployment to a new version.'
    }
    throw "Sheet sync failed: $message"
  }

  return $response
}

function Get-PngMetadataFromBytes {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  if ($Bytes.Length -lt 24) { throw 'PNG is truncated.' }
  $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
  for ($index = 0; $index -lt $signature.Length; $index++) {
    if ($Bytes[$index] -ne $signature[$index]) { throw 'Rendered raid image is not a PNG.' }
  }

  $width =
    ([int]$Bytes[16] -shl 24) -bor
    ([int]$Bytes[17] -shl 16) -bor
    ([int]$Bytes[18] -shl 8) -bor
    [int]$Bytes[19]
  $height =
    ([int]$Bytes[20] -shl 24) -bor
    ([int]$Bytes[21] -shl 16) -bor
    ([int]$Bytes[22] -shl 8) -bor
    [int]$Bytes[23]

  if ($width -le 0 -or $height -le 0) { throw 'Rendered PNG dimensions are invalid.' }
  return [pscustomobject]@{ Width = $width; Height = $height; Bytes = $Bytes.Length }
}

function Get-PngMetadata {
  param([Parameter(Mandatory)][string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  return Get-PngMetadataFromBytes -Bytes ([IO.File]::ReadAllBytes($resolved))
}

function Assert-RaidPngMetadata {
  param(
    [Parameter(Mandatory)]$Metadata,
    [Parameter(Mandatory)][int]$ExpectedWidth,
    [Parameter(Mandatory)][int]$ExpectedHeight,
    [int]$MaximumBytes = $script:DiscordMaxAttachmentBytes
  )

  if ($Metadata.Width -ne $ExpectedWidth -or [Math]::Abs($Metadata.Height - $ExpectedHeight) -gt 2) {
    throw "Raid PNG must be a native ${ExpectedWidth}px render near ${ExpectedWidth}x${ExpectedHeight}; received $($Metadata.Width)x$($Metadata.Height)."
  }
  if ($Metadata.Bytes -gt $MaximumBytes) {
    throw "Raid PNG is $($Metadata.Bytes) bytes and exceeds Discord's 10 MiB attachment limit."
  }
  return $true
}

function Test-RaidPngWhitespaceRow {
  param(
    [Parameter(Mandatory)][Drawing.Bitmap]$Bitmap,
    [Parameter(Mandatory)][int]$Y,
    [ValidateRange(0, 255)][int]$WhiteThreshold = 250
  )

  for ($x = 0; $x -lt $Bitmap.Width; $x++) {
    $pixel = $Bitmap.GetPixel($x, $Y)
    if (
      $pixel.A -ne 0 -and
      ($pixel.R -lt $WhiteThreshold -or $pixel.G -lt $WhiteThreshold -or $pixel.B -lt $WhiteThreshold)
    ) {
      return $false
    }
  }
  return $true
}

function Test-RaidPngWhitespaceColumn {
  param(
    [Parameter(Mandatory)][Drawing.Bitmap]$Bitmap,
    [Parameter(Mandatory)][int]$X,
    [ValidateRange(0, 255)][int]$WhiteThreshold = 250
  )

  for ($y = 0; $y -lt $Bitmap.Height; $y++) {
    $pixel = $Bitmap.GetPixel($X, $y)
    if (
      $pixel.A -ne 0 -and
      ($pixel.R -lt $WhiteThreshold -or $pixel.G -lt $WhiteThreshold -or $pixel.B -lt $WhiteThreshold)
    ) {
      return $false
    }
  }
  return $true
}

function Get-RaidPngOuterWhitespace {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(0, 255)][int]$WhiteThreshold = 250,
    [ValidateRange(1, 1024)][int]$MaximumMarginPixels = 256
  )

  Add-Type -AssemblyName System.Drawing
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  $bitmap = [Drawing.Bitmap]::FromFile($resolved)

  try {
    $top = 0
    while (
      $top -lt $bitmap.Height -and
      $top -lt $MaximumMarginPixels -and
      (Test-RaidPngWhitespaceRow -Bitmap $bitmap -Y $top -WhiteThreshold $WhiteThreshold)
    ) {
      $top++
    }

    $bottom = 0
    while (
      $bottom -lt ($bitmap.Height - $top) -and
      $bottom -lt $MaximumMarginPixels -and
      (Test-RaidPngWhitespaceRow -Bitmap $bitmap -Y ($bitmap.Height - 1 - $bottom) -WhiteThreshold $WhiteThreshold)
    ) {
      $bottom++
    }

    $left = 0
    while (
      $left -lt $bitmap.Width -and
      $left -lt $MaximumMarginPixels -and
      (Test-RaidPngWhitespaceColumn -Bitmap $bitmap -X $left -WhiteThreshold $WhiteThreshold)
    ) {
      $left++
    }

    $right = 0
    while (
      $right -lt ($bitmap.Width - $left) -and
      $right -lt $MaximumMarginPixels -and
      (Test-RaidPngWhitespaceColumn -Bitmap $bitmap -X ($bitmap.Width - 1 - $right) -WhiteThreshold $WhiteThreshold)
    ) {
      $right++
    }

    if (
      ($top -eq $MaximumMarginPixels -and $top -lt $bitmap.Height -and (Test-RaidPngWhitespaceRow -Bitmap $bitmap -Y $top -WhiteThreshold $WhiteThreshold)) -or
      ($bottom -eq $MaximumMarginPixels -and $bottom -lt ($bitmap.Height - $top) -and (Test-RaidPngWhitespaceRow -Bitmap $bitmap -Y ($bitmap.Height - 1 - $bottom) -WhiteThreshold $WhiteThreshold)) -or
      ($left -eq $MaximumMarginPixels -and $left -lt $bitmap.Width -and (Test-RaidPngWhitespaceColumn -Bitmap $bitmap -X $left -WhiteThreshold $WhiteThreshold)) -or
      ($right -eq $MaximumMarginPixels -and $right -lt ($bitmap.Width - $left) -and (Test-RaidPngWhitespaceColumn -Bitmap $bitmap -X ($bitmap.Width - 1 - $right) -WhiteThreshold $WhiteThreshold))
    ) {
      throw "Raid PNG outer whitespace exceeds the guarded ${MaximumMarginPixels}px limit."
    }

    if ($left + $right -ge $bitmap.Width -or $top + $bottom -ge $bitmap.Height) {
      throw 'Raid PNG contains no visible content inside its outer whitespace.'
    }

    return [pscustomobject]@{
      Left = $left
      Top = $top
      Right = $right
      Bottom = $bottom
    }
  } finally {
    $bitmap.Dispose()
  }
}

function Convert-RaidPngOuterWhitespaceToTransparency {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(0, 255)][int]$WhiteThreshold = 250,
    [ValidateRange(1, 1024)][int]$MaximumMarginPixels = 256
  )

  Add-Type -AssemblyName System.Drawing
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  $margins = Get-RaidPngOuterWhitespace -Path $resolved -WhiteThreshold $WhiteThreshold -MaximumMarginPixels $MaximumMarginPixels
  $bitmap = [Drawing.Bitmap]::FromFile($resolved)
  $stream = $null

  try {
    if ($bitmap.PixelFormat -ne [Drawing.Imaging.PixelFormat]::Format32bppArgb) {
      throw "Raid PNG must use 32-bit ARGB pixels before margin cleanup; received $($bitmap.PixelFormat)."
    }

    $transparentWhite = [Drawing.Color]::FromArgb(0, 255, 255, 255)

    for ($y = 0; $y -lt $margins.Top; $y++) {
      for ($x = 0; $x -lt $bitmap.Width; $x++) { $bitmap.SetPixel($x, $y, $transparentWhite) }
    }
    for ($y = $bitmap.Height - $margins.Bottom; $y -lt $bitmap.Height; $y++) {
      for ($x = 0; $x -lt $bitmap.Width; $x++) { $bitmap.SetPixel($x, $y, $transparentWhite) }
    }
    for ($x = 0; $x -lt $margins.Left; $x++) {
      for ($y = $margins.Top; $y -lt ($bitmap.Height - $margins.Bottom); $y++) { $bitmap.SetPixel($x, $y, $transparentWhite) }
    }
    for ($x = $bitmap.Width - $margins.Right; $x -lt $bitmap.Width; $x++) {
      for ($y = $margins.Top; $y -lt ($bitmap.Height - $margins.Bottom); $y++) { $bitmap.SetPixel($x, $y, $transparentWhite) }
    }

    $stream = New-Object IO.MemoryStream
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
  } finally {
    if ($stream) { $stream.Dispose() }
    $bitmap.Dispose()
  }

  [IO.File]::WriteAllBytes($resolved, $bytes)
  $metadata = Get-PngMetadata -Path $resolved
  return [pscustomobject]@{
    Width = $metadata.Width
    Height = $metadata.Height
    Bytes = $metadata.Bytes
    TransparentLeft = $margins.Left
    TransparentTop = $margins.Top
    TransparentRight = $margins.Right
    TransparentBottom = $margins.Bottom
  }
}

function Initialize-WindowsPdfRenderer {
  if ($script:WinRtPdfRendererInitialized) { return }

  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
  $null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType=WindowsRuntime]
  $null = [Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType=WindowsRuntime]
  $null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
  $null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime]

  $methods = [System.WindowsRuntimeSystemExtensions].GetMethods()
  $script:WinRtAsTaskOperation = $methods |
    Where-Object {
      $_.Name -eq 'AsTask' -and
      $_.IsGenericMethod -and
      $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } |
    Select-Object -First 1
  $script:WinRtAsTaskAction = $methods |
    Where-Object {
      $_.Name -eq 'AsTask' -and
      -not $_.IsGenericMethod -and
      $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    } |
    Select-Object -First 1

  if (-not $script:WinRtAsTaskOperation -or -not $script:WinRtAsTaskAction) {
    throw 'Windows PDF rendering support is unavailable on this PC.'
  }
  $script:WinRtPdfRendererInitialized = $true
}

function Wait-WinRtOperation {
  param([Parameter(Mandatory)]$Operation, [Parameter(Mandatory)][Type]$ResultType)
  $task = $script:WinRtAsTaskOperation.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  $task.Wait()
  return $task.Result
}

function Wait-WinRtAction {
  param([Parameter(Mandatory)]$Action)
  $task = $script:WinRtAsTaskAction.Invoke($null, @($Action))
  $task.Wait()
}

function Convert-CroppedPdfToRaidPng {
  param(
    [Parameter(Mandatory)][string]$PdfPath,
    [Parameter(Mandatory)][string]$PngPath,
    [ValidateRange(1024, 8192)][int]$TargetWidth = $script:RaidPngTargetWidth
  )

  Initialize-WindowsPdfRenderer
  $resolvedPdf = (Resolve-Path -LiteralPath $PdfPath -ErrorAction Stop).Path
  $resolvedPng = [IO.Path]::GetFullPath($PngPath)
  $page = $null
  $stream = $null
  $reader = $null

  try {
    $storageFile = Wait-WinRtOperation -Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($resolvedPdf)) -ResultType ([Windows.Storage.StorageFile])
    $document = Wait-WinRtOperation -Operation ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)) -ResultType ([Windows.Data.Pdf.PdfDocument])
    if ($document.PageCount -ne 1) { throw 'Raid PDF must contain exactly one page.' }

    $page = $document.GetPage(0)
    $destinationHeight = [uint32][Math]::Round($TargetWidth * $page.Size.Height / $page.Size.Width)
    $options = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    $options.DestinationWidth = [uint32]$TargetWidth
    $options.DestinationHeight = $destinationHeight
    $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream

    Wait-WinRtAction -Action ($page.RenderToStreamAsync($stream, $options))
    $stream.Seek(0)
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    $loaded = Wait-WinRtOperation -Operation ($reader.LoadAsync([uint32]$stream.Size)) -ResultType ([uint32])
    if ($loaded -ne $stream.Size) { throw 'Windows returned an incomplete PNG render.' }

    $bytes = New-Object byte[] ([int]$stream.Size)
    $reader.ReadBytes($bytes)
    [IO.File]::WriteAllBytes($resolvedPng, $bytes)
  } finally {
    if ($reader) { $reader.Dispose() }
    if ($stream) { $stream.Dispose() }
    if ($page) { $page.Dispose() }
  }

  return Get-PngMetadata -Path $resolvedPng
}

function New-PizzaRaidPlannerTempDirectory {
  $path = Join-Path ([IO.Path]::GetTempPath()) ('PizzaRaidPlanner-4K-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return [IO.Path]::GetFullPath($path)
}

function Remove-PizzaRaidPlannerTempDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
  $requiredPrefix = $tempRoot + '\PizzaRaidPlanner-4K-'
  if (-not $resolved.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove unexpected render directory: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Convert-PreparedRaidPdfs {
  param(
    [Parameter(Mandatory)][object[]]$PdfPayloads,
    [Parameter(Mandatory)][string]$TempDirectory
  )

  if (@($PdfPayloads).Count -ne 2) { throw 'The Apps Script response did not contain both raid PDFs.' }
  $allowedNames = @('blood_prince_council', 'blood_queen_lanathel')
  $seen = @{}
  $images = New-Object 'System.Collections.Generic.List[object]'

  foreach ($pdf in @($PdfPayloads)) {
    $safeName = [string]$pdf.safeName
    if ($safeName -notin $allowedNames -or $seen.ContainsKey($safeName)) {
      throw "Unexpected or duplicate raid PDF: $safeName"
    }
    $seen[$safeName] = $true

    $targetWidth = [int]$pdf.targetWidth
    $expectedHeight = [int]$pdf.expectedHeight
    if ($targetWidth -ne $script:RaidPngTargetWidth -or $expectedHeight -le 0) {
      throw "Invalid 4K render plan for $safeName."
    }

    $encoded = [string]$pdf.base64
    if (-not $encoded -or $encoded.Length -gt 30MB -or $encoded -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
      throw "Invalid PDF payload for $safeName."
    }
    try { $pdfBytes = [Convert]::FromBase64String($encoded) }
    catch { throw "Invalid Base64 PDF for $safeName." }
    if ($pdfBytes.Length -lt 5 -or [Text.Encoding]::ASCII.GetString($pdfBytes, 0, 5) -ne '%PDF-') {
      throw "The prepared $safeName file is not a PDF."
    }

    $pdfPath = Join-Path $TempDirectory ($safeName + '.pdf')
    $pngPath = Join-Path $TempDirectory ($safeName + '.png')
    [IO.File]::WriteAllBytes($pdfPath, $pdfBytes)
    Convert-CroppedPdfToRaidPng -PdfPath $pdfPath -PngPath $pngPath -TargetWidth $targetWidth | Out-Null
    $metadata = Convert-RaidPngOuterWhitespaceToTransparency -Path $pngPath
    Assert-RaidPngMetadata -Metadata $metadata -ExpectedWidth $targetWidth -ExpectedHeight $expectedHeight | Out-Null
    $pngBytes = [IO.File]::ReadAllBytes($pngPath)

    $images.Add([ordered]@{
      safeName = $safeName
      width = $metadata.Width
      height = $metadata.Height
      base64 = [Convert]::ToBase64String($pngBytes)
    })
  }

  return $images.ToArray()
}

function Invoke-PizzaRaidPlannerSheetSync {
  param(
    [string]$RequestedSavedVariablesPath,
    [switch]$ForceConfigure,
    [switch]$PermitStale,
    [int]$MaxAgeMinutes,
    [switch]$PublishToDiscord,
    [switch]$ValidateOnly
  )

  $config = if ($ValidateOnly) { $null } else { Get-SheetSyncConfig -ForceConfigure:$ForceConfigure -PreferredSavedVariablesPath $RequestedSavedVariablesPath }
  $sourcePath = if ($RequestedSavedVariablesPath) {
    $RequestedSavedVariablesPath
  } elseif ($config -and $config.SavedVariablesPath) {
    [string]$config.SavedVariablesPath
  } else {
    $script:DefaultSavedVariablesPath
  }
  if (-not $sourcePath) {
    throw 'No SavedVariables path is configured. Run the desktop setup once and select WTF\Account\YOUR_ACCOUNT\SavedVariables\PizzaRaidPlanner.lua.'
  }
  $source = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
  $age = [DateTime]::UtcNow - $source.LastWriteTimeUtc
  if (-not $PermitStale -and $age.TotalMinutes -gt $MaxAgeMinutes) {
    throw "SavedVariables were last written $([math]::Floor($age.TotalMinutes)) minutes ago. Type /reload in WoW so the selected Festergut plan is flushed, then run the icon again."
  }

  $raw = [IO.File]::ReadAllText($source.FullName, [Text.Encoding]::UTF8)
  $bpcTsv = Get-Base64ExportPayload -SavedVariablesText $raw -Name 'bpcTSVB64'
  $bqlTsv = Get-Base64ExportPayload -SavedVariablesText $raw -Name 'planTSVB64'
  $combinedTsv = Merge-PizzaRaidPlannerTsv -BpcTsv $bpcTsv -BqlTsv $bqlTsv
  $rows = @(Get-TsvLines -Value $combinedTsv).Count

  if ($ValidateOnly) {
    return [pscustomobject]@{ Ok = $true; Rows = $rows; BqlStartRow = $script:BqlStartRow; Source = $source.FullName }
  }

  $token = Unprotect-SyncToken -EncryptedToken ([string]$config.EncryptedToken)
  $sourceWrittenAt = $source.LastWriteTime.ToString('o')
  $initialAction = Get-PizzaRaidPlannerDesktopAction -PublishToDiscord:$PublishToDiscord
  $initialPayload = @{
    action = $initialAction
    token = $token
    tsv = $combinedTsv
    sourceWrittenAt = $sourceWrittenAt
    addonVersion = '1.0.1'
  }

  if ($PublishToDiscord) {
    $prepareResponse = Invoke-PizzaRaidPlannerEndpoint `
      -Endpoint ([string]$config.Endpoint) `
      -Payload $initialPayload `
      -TimeoutSeconds 240

    if (
      -not $prepareResponse.PSObject.Properties['publishProtocol'] -or
      [int]$prepareResponse.publishProtocol -ne $script:PublishProtocolVersion
    ) {
      throw 'The Google Apps Script deployment did not return the 4K publishing protocol. Update the existing deployment to the latest DiscordPost.gs version.'
    }

    if ($prepareResponse.alreadyPublished) {
      $response = $prepareResponse
    } else {
      if (-not $prepareResponse.publishTicket) { throw 'The Apps Script response did not include a 4K publish ticket.' }
      $tempDirectory = New-PizzaRaidPlannerTempDirectory
      try {
        $images = @(Convert-PreparedRaidPdfs -PdfPayloads @($prepareResponse.pdfs) -TempDirectory $tempDirectory)
        $completePayload = @{
          action = 'completeRaidPlanPublish'
          publishProtocol = $script:PublishProtocolVersion
          publishTicket = [string]$prepareResponse.publishTicket
          token = $token
          tsv = $combinedTsv
          sourceWrittenAt = $sourceWrittenAt
          addonVersion = '1.0.1'
          images = $images
        }
        $response = Invoke-PizzaRaidPlannerEndpoint `
          -Endpoint ([string]$config.Endpoint) `
          -Payload $completePayload `
          -TimeoutSeconds 240
      } finally {
        try { Remove-PizzaRaidPlannerTempDirectory -Path $tempDirectory }
        catch { Write-Warning "Could not remove the temporary 4K render directory: $($_.Exception.Message)" }
      }
    }
  } else {
    $response = Invoke-PizzaRaidPlannerEndpoint `
      -Endpoint ([string]$config.Endpoint) `
      -Payload $initialPayload `
      -TimeoutSeconds 45
  }

  New-Item -ItemType Directory -Path $script:ConfigDirectory -Force | Out-Null
  [IO.File]::WriteAllText($script:LastUploadPath, $combinedTsv, [Text.UTF8Encoding]::new($false))
  $audit = [ordered]@{
    SyncedAt = (Get-Date).ToString('o')
    SourceWrittenAt = $sourceWrittenAt
    Action = [string]$response.action
    Sheet = [string]$response.sheet
    Range = [string]$response.range
    Rows = [int]$response.rows
    Columns = [int]$response.columns
  }
  if ($PublishToDiscord) {
    $audit.LiveSheets = @($response.liveSheets)
    $audit.DiscordPosted = [bool]$response.discordPosted
    $audit.AlreadyPublished = [bool]$response.alreadyPublished
    $audit.PublishedAt = [string]$response.publishedAt
    $audit.PublishProtocol = [int]$response.publishProtocol
    if ($response.PSObject.Properties['imageDetails']) {
      $audit.Images = @($response.imageDetails)
    }
    if ($response.PSObject.Properties['discordConfirmation']) {
      $audit.DiscordConfirmation = [string]$response.discordConfirmation
    }
    if ($response.PSObject.Properties['discordMessageId']) {
      $audit.DiscordMessageId = [string]$response.discordMessageId
    }
  }
  [IO.File]::WriteAllText($script:LastSyncPath, ($audit | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  if (Test-Path -LiteralPath $script:LastErrorPath -PathType Leaf) {
    Remove-Item -LiteralPath $script:LastErrorPath -Force -ErrorAction SilentlyContinue
  }

  if ($PublishToDiscord -and $response.alreadyPublished) {
    Show-SyncMessage -Title 'Pizza Warriors Raid Publisher' -Text "This exact Festergut plan was already published.`r`n`r`nNothing was posted to Discord twice.`r`nOriginal publish: $($response.publishedAt)"
  } elseif ($PublishToDiscord) {
    Show-SyncMessage -Title 'Pizza Warriors Raid Publisher' -Text "Raid positions published successfully.`r`n`r`nLive sheets updated:`r`n- Blood Prince Council`r`n- Blood Queen Lana'Thel`r`n`r`nDiscord: native 4096px BPC and BQL images posted to #raid-positions."
  } else {
    Show-SyncMessage -Text "WoW TSV Dump was replaced successfully.`r`n`r`nUploaded: $($response.range)`r`nBPC starts: A1`r`nBQL starts: A55`r`n`r`nYou can now values-only copy the printed blocks into the BPC and BQL tabs, then publish to Discord."
  }
  return [pscustomobject]$audit
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $syncArguments = @{
      RequestedSavedVariablesPath = $SavedVariablesPath
      ForceConfigure = $Configure
      PermitStale = $AllowStale
      MaxAgeMinutes = $MaximumAgeMinutes
      PublishToDiscord = $Publish
      ValidateOnly = $DryRun
    }
    Invoke-PizzaRaidPlannerSheetSync @syncArguments | Format-List
  } catch {
    $failure = $_
    try { Write-SyncFailureLog -ErrorRecord $failure } catch { }
    try {
      Show-SyncMessage -Title 'Pizza Warriors Raid Publisher' -Text "$($failure.Exception.Message)`r`n`r`nDetails were saved to:`r`n$script:LastErrorPath" -Icon 'Error'
    } catch {
      [Console]::Error.WriteLine("Pizza Warriors Raid Publisher failed: $($failure.Exception.Message)")
      [Console]::Error.WriteLine("Details: $script:LastErrorPath")
    }
    exit 1
  }
}
