param(
  [Parameter(Mandatory=$true)]
  [string]$TenantId,

  [Parameter(Mandatory=$true)]
  [string]$ClientId,

  [Parameter(Mandatory=$true)]
  [string]$CertThumbprint,

  [Parameter(Mandatory=$true)]
  [string]$UpnFile,

  [Parameter(Mandatory=$true)]
  [string]$OutputDir,

  [switch]$IncludePhoto,          # désactivé par défaut
  [switch]$ForceOverwrite         # force l’écriture même si identique
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Escape-VCardValue([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  # vCard escaping (3.0) : \, ; , et sauts de ligne
  $s = $s -replace "\\","\\\\"
  $s = $s -replace ";","\;"
  $s = $s -replace ",","\,"
  $s = $s -replace "`r`n","\\n"
  $s = $s -replace "`n","\\n"
  $s = $s -replace "`r","\\n"
  return $s
}

function New-VCardFromUser($u, [byte[]]$photoBytes) {
  $crlf = "`r`n"

  $fn        = Escape-VCardValue($u.DisplayName)
  $given     = Escape-VCardValue($u.GivenName)
  $surname   = Escape-VCardValue($u.Surname)
  $jobTitle  = Escape-VCardValue($u.JobTitle)
  $dept      = Escape-VCardValue($u.Department)
  $company   = Escape-VCardValue($u.CompanyName)
  $office    = Escape-VCardValue($u.OfficeLocation)

  $email     = Escape-VCardValue($u.Mail)
  if ([string]::IsNullOrWhiteSpace($email)) { $email = Escape-VCardValue($u.UserPrincipalName) }

  $mobile    = Escape-VCardValue($u.MobilePhone)
  $bizPhones = @()
  if ($u.BusinessPhones) { $bizPhones = $u.BusinessPhones | ForEach-Object { Escape-VCardValue($_) } }

  $street    = Escape-VCardValue($u.StreetAddress)
  $city      = Escape-VCardValue($u.City)
  $state     = Escape-VCardValue($u.State)
  $zip       = Escape-VCardValue($u.PostalCode)
  $country   = Escape-VCardValue($u.Country)

  # UID stable : on préfère l'Id Graph
  $uid       = Escape-VCardValue($u.Id)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("BEGIN:VCARD")
  $lines.Add("VERSION:3.0")
  $lines.Add("PRODID:-//Magora//VCF Exporter//FR")
  if ($uid) { $lines.Add("UID:$uid") }
  if ($fn)  { $lines.Add("FN:$fn") }
  $lines.Add("N:$surname;$given;;;")

  if ($company -or $dept) {
    # ORG peut contenir des niveaux séparés par ';'
    # on met CompanyName ; Department
    $org = "$company;$dept"
    $org = $org.Trim(";")
    $lines.Add("ORG:$org")
  }

  if ($jobTitle) { $lines.Add("TITLE:$jobTitle") }
  if ($office)   { $lines.Add("X-OFFICE:$office") }

  if ($email)    { $lines.Add("EMAIL;TYPE=INTERNET,WORK:$email") }
  if ($mobile)   { $lines.Add("TEL;TYPE=CELL:$mobile") }
  foreach ($bp in $bizPhones) {
    if ($bp) { $lines.Add("TEL;TYPE=WORK,VOICE:$bp") }
  }

  if ($street -or $city -or $state -or $zip -or $country) {
    # ADR;TYPE=WORK:;;street;city;state;zip;country
    $lines.Add("ADR;TYPE=WORK:;;$street;$city;$state;$zip;$country")
  }

  if ($IncludePhoto -and $photoBytes -and $photoBytes.Length -gt 0) {
    $b64 = [Convert]::ToBase64String($photoBytes)
    # vCard 3.0 PHOTO en base64 (peut grossir les fichiers)
    $lines.Add("PHOTO;ENCODING=b;TYPE=JPEG:$b64")
  }

  $lines.Add("END:VCARD")

  # vCard préfère CRLF
  return ($lines -join $crlf) + $crlf
}

Ensure-Dir $OutputDir

Write-Host "Connecting to Microsoft Graph (App-Only)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumbprint | Out-Null

$ctx = Get-MgContext
Write-Host "Connected. AuthType = $($ctx.AuthType)" -ForegroundColor Green

# Charge la liste UPNs
if (-not (Test-Path $UpnFile)) { throw "UPN file not found: $UpnFile" }
$upns = @(
  Get-Content $UpnFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Select-Object -Unique
)

Write-Host "UPNs loaded: $($upns.Count)" -ForegroundColor Cyan

$results = New-Object System.Collections.Generic.List[object]

foreach ($upn in $upns) {
  try {
    Write-Host "Processing $upn ..." -ForegroundColor White

    # Propriétés utiles pour vCard
    $u = Get-MgUser -UserId $upn -Property @(
      "id","displayName","givenName","surname","mail","userPrincipalName",
      "mobilePhone","businessPhones","jobTitle","department","companyName",
      "officeLocation","streetAddress","city","state","postalCode","country"
    )

    $photoBytes = $null
    if ($IncludePhoto) {
      try {
        # Optionnel : photo (requiert permissions adéquates)
        $photoBytes = Get-MgUserPhotoContent -UserId $u.Id
      } catch {
        # non bloquant
        $photoBytes = $null
      }
    }

    $vcf = New-VCardFromUser -u $u -photoBytes $photoBytes

    # Nom de fichier safe
    $safe = ($u.UserPrincipalName -replace "[^a-zA-Z0-9@\.\-_]","_")
    $path = Join-Path $OutputDir "$safe.vcf"

    $write = $true
    $reason = "created"

    if (Test-Path $path) {
      $existing = Get-Content -Raw -Encoding UTF8 $path
      if (-not $ForceOverwrite -and $existing -eq $vcf) {
        $write = $false
        $reason = "unchanged"
      } else {
        $reason = "updated"
      }
    }

    if ($write) {
      # UTF8 sans BOM préférable
      [System.IO.File]::WriteAllText($path, $vcf, (New-Object System.Text.UTF8Encoding($false)))
    }

    $results.Add([pscustomobject]@{
      UPN    = $upn
      File   = $path
      Status = $reason
    }) | Out-Null

  } catch {
    $results.Add([pscustomobject]@{
      UPN    = $upn
      File   = $null
      Status = "error: $($_.Exception.Message)"
    }) | Out-Null
    Write-Host "ERROR on $upn : $($_.Exception.Message)" -ForegroundColor Red
  }
}

# Export log
$logPath = Join-Path $OutputDir ("vcf-export-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
$results | Export-Csv -NoTypeInformation -Encoding UTF8 $logPath

Write-Host "Done. Log: $logPath" -ForegroundColor Green