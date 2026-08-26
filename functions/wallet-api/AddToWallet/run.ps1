using namespace System.Net

param($Request, $TriggerMetadata)

. "$PSScriptRoot/../Shared/Cors.ps1"
. "$PSScriptRoot/../Shared/GraphAuth.ps1"
. "$PSScriptRoot/../Shared/VCardBuilder.ps1"
. "$PSScriptRoot/../Shared/Pass2U.ps1"

$corsHeaders = Get-CorsHeaders -Request $Request

function Send-JsonResponse {
  param([int]$StatusCode, [hashtable]$Body)
  Push-OutputBinding -Name Response -InputObject ([HttpResponseContext]@{
    StatusCode = $StatusCode
    Headers    = $corsHeaders + @{ "Content-Type" = "application/json" }
    Body       = ($Body | ConvertTo-Json -Depth 5)
  })
}

if (Test-IsPreflightRequest -Request $Request) {
  Push-OutputBinding -Name Response -InputObject ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::NoContent
    Headers    = $corsHeaders
  })
  return
}

try {
  $me = Get-ValidatedGraphIdentity -Request $Request -ExpectedTenantId $env:GRAPH_TENANT_ID
} catch [System.UnauthorizedAccessException] {
  Send-JsonResponse -StatusCode 401 -Body @{ error = $_.Exception.Message }
  return
}

$fields = $Request.Body
if (-not $fields) {
  Send-JsonResponse -StatusCode 400 -Body @{ error = "Corps de requête JSON manquant." }
  return
}

# Le corps arrive en PSCustomObject : on le convertit en hashtable pour VCardBuilder.
$fieldsHash = @{}
foreach ($prop in $fields.PSObject.Properties) { $fieldsHash[$prop.Name] = $prop.Value }

$vcardText = New-VCardFromFields -Id $me.id -Fields $fieldsHash

# Écrase le snapshot précédent (usage unique : pas de fusion avec un profil mémorisé).
Push-OutputBinding -Name vCardTable -InputObject @{
  PartitionKey = "vcard"
  RowKey       = $me.id
  Content      = $vcardText
}

$functionBaseUrl = $Request.Url.GetLeftPart([System.UriPartial]::Authority)
$barcodeUrl = "$functionBaseUrl/api/vcard/$($me.id)"

try {
  $pass = Invoke-Pass2UCreatePass -BarcodeUrl $barcodeUrl -Fields $fieldsHash
} catch {
  Send-JsonResponse -StatusCode 502 -Body @{ error = "Échec de la génération du pass Wallet : $($_.Exception.Message)" }
  return
}

Send-JsonResponse -StatusCode 200 -Body @{ walletUrl = $pass.walletUrl }
