<#
.SYNOPSIS
  Génère des QR codes en lot à partir des fichiers présents dans un dossier.
  URL = BaseUrl + (nom du fichier sans extension par défaut)
  Nom du QR = (nom du fichier sans extension).png (ou .svg)

.EXAMPLE
  .\New-QRCode.ps1 -SourceDir ".\contacts" -OutputDir ".\qrcodes" -AutoDownload

.EXAMPLE
  # uniquement les .vcf, et on garde l'extension dans l'URL
  .\New-QRCode.ps1 -SourceDir ".\contacts" -OutputDir ".\qrcodes" -Filter "*.vcf" -UseFullFileName -AutoDownload

.EXAMPLE
  # sous-dossiers inclus, correction d'erreur haute, overwrite
  .\New-QRCode.ps1 -SourceDir ".\contacts" -OutputDir ".\qrcodes" -Recurse -ErrorCorrectionLevel H -Force -AutoDownload
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$SourceDir,

  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$OutputDir,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$BaseUrl = "https://becjaune.github.io/Cards/contacts/",

  # Filtre de fichiers (ex: "*.html", "*.vcf", "*.json"). Par défaut: tous les fichiers
  [string]$Filter = "*.*",

  # Inclure sous-dossiers
  [switch]$Recurse,

  # Par défaut on utilise le nom sans extension (BaseName). Si activé -> on utilise le nom complet (FileName.ext)
  [switch]$UseFullFileName,

  [ValidateSet("png","svg")]
  [string]$Format = "png",

  [ValidateRange(2,50)]
  [int]$PixelsPerModule = 10,

  [ValidateSet("L","M","Q","H")]
  [string]$ErrorCorrectionLevel = "M",

  # Téléchargement auto de QRCoder (NuGet) si la DLL n'est pas déjà localement disponible
  [switch]$AutoDownload,

  # Remplace les caractères invalides pour Windows dans le nom du fichier du QR
  [switch]$SanitizeFileName,

  # Overwrite si existe
  [switch]$Force,

  # Exporter un manifest CSV (nom/url/fichier/status)
  [switch]$WriteManifest,

  # Générer le CSV contacts demandé
  [switch]$WriteContactsCsv,

  # Chemin du fichier upns.txt pour enrichir les contacts
  [string]$UpnsFile = (Join-Path (Split-Path $PSScriptRoot -Parent) "upns.txt")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
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
  return ($name -replace '[<>:"/\\|?*\x00-\x1F]', '_')
}

function Parse-VCard([string]$Path) {
  $content = Get-Content -Path $Path -ErrorAction Stop
  $contact = [PSCustomObject]@{
    Email = ""
    Name  = ""
    Mobile = ""
  }

  foreach ($line in $content) {
    if ($line -match '^FN:(.+)$') {
      $contact.Name = $matches[1].Trim()
    } elseif ($line -match '^EMAIL[^:]*:(.+)$') {
      if (-not $contact.Email) { $contact.Email = $matches[1].Trim() }
    } elseif ($line -match '^TEL[^:]*:(.+)$') {
      if (-not $contact.Mobile) { $contact.Mobile = $matches[1].Trim() }
    }
  }

  return $contact
}

function Ensure-TrailingSlash([string]$Url) {
  if (-not $Url.EndsWith('/')) { return $Url + '/' }
  return $Url
}

# ---- Validations
if (-not (Test-Path $SourceDir)) { throw "SourceDir introuvable: $SourceDir" }
Ensure-Dir $OutputDir

# ---- Load QRCoder
$dll = Resolve-QRCoderAssembly -AutoDownload:$AutoDownload
Add-Type -Path $dll

$generator = New-Object QRCoder.QRCodeGenerator
$ecc = Map-EccLevel $ErrorCorrectionLevel

# ---- Get files
$gciParams = @{
  Path   = $SourceDir
  Filter = $Filter
  File   = $true
}
if ($Recurse) { $gciParams.Recurse = $true }

$files = Get-ChildItem @gciParams
$files = @($files) # force array

Write-Host "Fichiers trouvés: $($files.Count)" -ForegroundColor Cyan
Write-Host "BaseUrl: $BaseUrl" -ForegroundColor Cyan
Write-Host "Sortie: $OutputDir ($Format)" -ForegroundColor Cyan

$manifest = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
  $suffix = if ($UseFullFileName) { $f.Name } else { $f.BaseName }

  # Si le suffixe contient des espaces/accents, c'est généralement OK dans une URL, mais selon ton site
  # tu peux vouloir encoder. Dis-moi si besoin -> j'ajoute l'URL encoding.
  $url = "$BaseUrl$suffix"

  $safeSuffix = Get-SafeFileName -name $suffix -sanitize:$SanitizeFileName
  $outPath = Join-Path $OutputDir ($safeSuffix + "." + $Format)

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

    if ($WriteManifest) {
      $manifest.Add([pscustomobject]@{
        SourceFile = $f.FullName
        Suffix     = $suffix
        Url        = $url
        QrFile     = $outPath
        Status     = $status
      }) | Out-Null
    }

  } catch {
    Write-Host "ERROR sur '$($f.FullName)' : $($_.Exception.Message)" -ForegroundColor Red
    if ($WriteManifest) {
      $manifest.Add([pscustomobject]@{
        SourceFile = $f.FullName
        Suffix     = $suffix
        Url        = $url
        QrFile     = $outPath
        Status     = "error: $($_.Exception.Message)"
      }) | Out-Null
    }
  }
}

if ($WriteManifest) {
  $manifestPath = Join-Path $OutputDir ("qrcode-manifest-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
  $manifest | Export-Csv -NoTypeInformation -Encoding UTF8 $manifestPath
  Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
}

if ($WriteContactsCsv) {
  if (-not (Test-Path $UpnsFile)) { throw "UpnsFile introuvable: $UpnsFile" }

  $BaseUrl = Ensure-TrailingSlash $BaseUrl
  $QrCodesBaseUrl = Ensure-TrailingSlash "https://becjaune.github.io/Cards/qrcodes/"
  $upns = Get-Content -Path $UpnsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  $upnsSet = @{}
  foreach ($upn in $upns) {
    $upnsSet[$upn.ToLower()] = $true
  }

  $vcfParams = @{ Path = $SourceDir; Filter = '*.vcf'; File = $true }
  if ($Recurse) { $vcfParams.Recurse = $true }
  $vcfFiles = Get-ChildItem @vcfParams

  $contacts = @{}
  foreach ($vcf in $vcfFiles) {
    $info = Parse-VCard $vcf.FullName
    if ($info.Email) { $contacts[$info.Email.ToLower()] = $info }
  }

  $qrParams = @{ Path = $OutputDir; Filter = "*.$Format"; File = $true }
  $qrFiles = Get-ChildItem @qrParams | Sort-Object @{ Expression = { $_.Name -like '*.vcf.*' }; Descending = $true }
  $seen = @{}

  $rows = foreach ($qrFile in $qrFiles) {
    $name = $qrFile.BaseName
    if ($name.EndsWith('.vcf')) { $name = $name.Substring(0, $name.Length - 4) }

    $emailKey = $name.ToLower()
    if (($upnsSet.Count -gt 0) -and -not $upnsSet.ContainsKey($emailKey)) { continue }
    if ($seen.ContainsKey($emailKey)) { continue }
    $seen[$emailKey] = $true

    $contact = $null
    if ($contacts.ContainsKey($emailKey)) { $contact = $contacts[$emailKey] }

    [PSCustomObject]@{
      barcode = "$QrCodesBaseUrl$($qrFile.Name)"
      expirationDate = ''
      'Name(Nom)' = if ($contact) { $contact.Name } else { '' }
      'Mobile(Mobile)' = if ($contact) { $contact.Mobile } else { '' }
      'Email(Email)' = if ($contact) { $contact.Email } else { $name }
      'Role()' = ''
    }
  }

  $csvPath = Join-Path $OutputDir ("qrcode-contacts-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath
  # Add UTF-8 BOM if missing so apps that expect a BOM (like some mobile importers)
  # will correctly detect UTF-8 and display accents (e.g. "Stéphane").
  $bytes = [System.IO.File]::ReadAllBytes($csvPath)
  if (($bytes.Length -lt 3) -or -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
    $bom = [byte[]](0xEF,0xBB,0xBF)
    [System.IO.File]::WriteAllBytes($csvPath, $bom + $bytes)
  }
  Write-Host "CSV contacts: $csvPath (with UTF-8 BOM)" -ForegroundColor Cyan
}

Write-Host "Terminé ✅" -ForegroundColor Green