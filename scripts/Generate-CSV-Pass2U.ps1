# Script to generate CSV file for Pass2U
# Reads UPNs from upns.txt and creates CSV with contact information

function Get-SafeFileName([string]$name) {
    return ($name -replace '[<>:"/\\|?*\x00-\x1F]', '_')
}

function Parse-VCard([string]$path) {
    $contact = [PSCustomObject]@{
        Email = ''
        Name  = ''
        Mobile = ''
    }

    if (-not (Test-Path $path)) { return $contact }

    foreach ($line in Get-Content -Path $path -ErrorAction Stop) {
        if ($line -match '^FN:(.+)$') {
            $contact.Name = $matches[1].Trim()
        }
        elseif ($line -match '^EMAIL[^:]*:(.+)$') {
            if (-not $contact.Email) { $contact.Email = $matches[1].Trim() }
        }
        elseif ($line -match '^TEL[^:]*:(.+)$') {
            if (-not $contact.Mobile) { $contact.Mobile = $matches[1].Trim() }
        }
    }

    return $contact
}

# Define paths
$scriptDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } elseif ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$contactsDir = Join-Path $scriptDir "..\contacts"
#$qrcodesDir = Join-Path $scriptDir "..\qrcodes"
$upnFile = Join-Path $scriptDir "..\upns.txt"
$csvFile = Join-Path $contactsDir "pass2u.csv"

# Read UPNs from file
if (-not (Test-Path $upnFile)) {
    Write-Host "Error: upns.txt introuvable à $upnFile"
    exit 1
}

$upns = Get-Content -Path $upnFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$upnSet = @{ }
foreach ($upn in $upns) {
    $upnSet[$upn.ToLower()] = $true
}

# Read contact data from VCF files
$contacts = @{ }
if (Test-Path $contactsDir) {
    foreach ($vcf in Get-ChildItem -Path $contactsDir -Filter '*.vcf' -File) {
        $info = Parse-VCard $vcf.FullName
        if ($info.Email) {
            $contacts[$info.Email.ToLower()] = $info
        }
    }
}

# Build rows from contact files
$rows = @()

foreach ($vcf in Get-ChildItem -Path $contactsDir -Filter '*.vcf' -File) {
    $emailKey = $vcf.BaseName.ToLower()
    if (($upnSet.Count -gt 0) -and -not $upnSet.ContainsKey($emailKey)) {
        continue
    }

    $contact = $contacts[$emailKey]

    $rows += [PSCustomObject]@{
        'barcode' = "https://becjaune.github.io/Cards/contacts/$($vcf.Name)"
        'expirationDate' = ''
        'Nom(Nom)' = if ($contact) { $contact.Name } else { '' }
        'Mobile(Mobile)' = if ($contact) { $contact.Mobile } else { '' }
        'Email(Email)' = if ($contact) { $contact.Email } else { $emailKey }
        'Role()' = ''
    }
}

if ($rows.Count -gt 0) {
    $rows | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Force
    $bytes = [System.IO.File]::ReadAllBytes($csvFile)
    if (($bytes.Length -lt 3) -or -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $bom = [byte[]](0xEF,0xBB,0xBF)
        [System.IO.File]::WriteAllBytes($csvFile, $bom + $bytes)
    }
    Write-Host "CSV file created successfully: $csvFile"
}
else {
    Write-Host "No data to export"
}
