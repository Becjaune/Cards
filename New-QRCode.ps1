<#
.SYNOPSIS
  Génère en lot des QR codes à partir d'un fichier de lignes.
  URL = BaseUrl + Line
  Nom fichier = Line.png (ou .svg)

.EXAMPLE
  .\New-QRCodeBatch.ps1 -InputFile .\codes.txt -OutputDir .\qrcodes -AutoDownload

.EXAMPLE
  .\New-QRCode.ps1 -InputFile .\comex.txt -OutputDir .\qrcodes -Format svg -AutoDownload
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$InputFile,

  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$OutputDir,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$BaseUrl = "https://becjaune.github.io/Cards/",

  [ValidateSet("png","svg")]
  [string]$Format = "png",

  [ValidateRange(2,50)]
  [int]$PixelsPerModule = 10,

  [ValidateSet("L","M","Q","H")]
  [string]$ErrorCorrectionLevel = "M",

  [switch]$AutoDownload,

  # si une ligne contient des caractères non valides pour un nom de fichier,
  # on les remplace par "_"
  [switch]$SanitizeFileName,

  # génère un manifest CSV avec line/url/file/status
  [switch]$WriteManifest,

  # si le fichier existe déjà : overwrite
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Resolve-QRCoderAssembly {
  param([switch]$AutoDownload)

  $libRoot = Join-Path $PSScriptRoot ".lib"
  $dllPath = Join-Path $libRoot "QRCoder.dll"

  if (Test-Path $dllPath) { return $dllPath }

  if (-not $AutoDownload) {
    throw "QRCoder.dll introuvable. Relance avec -AutoDownload, ou dépose la DLL ici: $dllPath"
  }

  Ensure-Dir $libRoot

  $version = "1.4.3"
  $nupkgUrl = "https://www.nuget.org/api/v2/package/QRCoder/$version"
  $nupkgPath = Join-Path $libRoot "QRCoder.$version.nupkg"
  $zipPath   = Join-Path $libRoot "QRCoder.$version.zip"
  $extractPath = Join-Path $libRoot "QRCoder.$version"

  Write-Host "Téléchargement QRCoder $version depuis NuGet..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath -UseBasicParsing

  Copy-Item $nupkgPath $zipPath -Force
  if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
  Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

  $candidate = Get-ChildItem -Path $extractPath -Recurse -Filter "QRCoder.dll" |
    Where-Object { $_.FullName -match "lib\\netstandard2\.0|lib\\net6\.0|lib\\net5\.0|lib\\netcoreapp" } |
    Select-Object -First 1

  if (-not $candidate) {
    $candidate = Get-ChildItem -Path $extractPath -Recurse -Filter "QRCoder.dll" | Select-Object -First 1
  }
  if (-not $candidate) { throw "Impossible de trouver QRCoder.dll dans le package NuGet." }

  Copy-Item $candidate.FullName $dllPath -Force
  return $dllPath
}

function Map-EccLevel([string]$level) {
  switch ($level) {
    "L" { return [QRCoder.QRCodeGenerator+ECCLevel]::L }
    "M" { return [QRCoder.QRCodeGenerator+ECCLevel]::M }
    "Q" { return [QRCoder.QRCodeGenerator+ECCLevel]::Q }
    "H" { return [QRCoder.QRCodeGenerator+ECCLevel]::H }
  }
}

function Get-SafeFileName([string]$name, [switch]$sanitize) {
  if (-not $sanitize) { return $name }
  # remplace tout caractère interdit Windows par "_"
  return ($name -replace '[<>:"/\\|?*\x00-\x1F]', '_')
}

# ---- Validations ----
if (-not (Test-Path $InputFile)) { throw "InputFile introuvable: $InputFile" }
Ensure-Dir $OutputDir

# ---- Load QRCoder ----
$dll = Resolve-QRCoderAssembly -AutoDownload:$AutoDownload
Add-Type -Path $dll

$generator = New-Object QRCoder.QRCodeGenerator
$ecc = Map-EccLevel $ErrorCorrectionLevel

# ---- Read lines ----
$lines = Get-Content $InputFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") }
$lines = @($lines)  # force array

Write-Host "Lignes à traiter: $($lines.Count)" -ForegroundColor Cyan
Write-Host "BaseUrl: $BaseUrl" -ForegroundColor Cyan
Write-Host "Sortie: $OutputDir ($Format)" -ForegroundColor Cyan

$manifest = New-Object System.Collections.Generic.List[object]

foreach ($line in $lines) {
  $safeName = Get-SafeFileName -name $line -sanitize:$SanitizeFileName
  $url = "$BaseUrl$line"

  $outPath = Join-Path $OutputDir ($safeName + "." + $Format)

  try {
    if ((Test-Path $outPath) -and -not $Force) {
      $status = "skipped_exists"
      Write-Host "SKIP (existe) : $outPath" -ForegroundColor Yellow
    } else {
      $data = $generator.CreateQrCode($url, $ecc)

      switch ($Format) {
        "png" {
          $pngQr = New-Object QRCoder.PngByteQRCode($data)
          $bytes = $pngQr.GetGraphic($PixelsPerModule)
          [System.IO.File]::WriteAllBytes($outPath, $bytes)
        }
        "svg" {
          $svgQr = New-Object QRCoder.SvgQRCode($data)
          $svg = $svgQr.GetGraphic($PixelsPerModule)
          [System.IO.File]::WriteAllText($outPath, $svg, (New-Object System.Text.UTF8Encoding($false)))
        }
      }

      $status = "generated"
      Write-Host "OK : $outPath  <=  $url" -ForegroundColor Green
    }

    $manifest.Add([pscustomobject]@{
      Line   = $line
      Url    = $url
      File   = $outPath
      Status = $status
    }) | Out-Null

  } catch {
    Write-Host "ERROR sur '$line' : $($_.Exception.Message)" -ForegroundColor Red
    $manifest.Add([pscustomobject]@{
      Line   = $line
      Url    = $url
      File   = $outPath
      Status = "error: $($_.Exception.Message)"
    }) | Out-Null
  }
}

if ($WriteManifest) {
  $manifestPath = Join-Path $OutputDir ("qrcode-manifest-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
  $manifest | Export-Csv -NoTypeInformation -Encoding UTF8 $manifestPath
  Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
}

Write-Host "Terminé ✅" -ForegroundColor Green