# Valide l'identité de l'appelant en relayant son token vers Microsoft Graph /me plutôt qu'en
# vérifiant nous-mêmes signature/audience/issuer : si Graph répond 200, le token est valide.
# Un décodage non-vérifié du payload permet un rejet rapide avant l'appel réseau.

function Get-BearerToken {
  param([Parameter(Mandatory)] $Request)

  $authHeader = $Request.Headers["Authorization"]
  if (-not $authHeader -or -not $authHeader.StartsWith("Bearer ")) {
    return $null
  }
  return $authHeader.Substring("Bearer ".Length).Trim()
}

function Test-QuickJwtSanityCheck {
  param([Parameter(Mandatory)] [string]$Token, [string]$ExpectedTenantId)

  $parts = $Token.Split(".")
  if ($parts.Count -lt 2) { return $false }

  try {
    $payloadB64 = $parts[1].Replace("-", "+").Replace("_", "/")
    switch ($payloadB64.Length % 4) { 2 { $payloadB64 += "==" } 3 { $payloadB64 += "=" } }
    $payloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadB64))
    $payload = $payloadJson | ConvertFrom-Json

    # Graph API v1.0 : audience attendue = "00000003-0000-0000-c000-000000000000" ou son URI.
    $isGraphAudience = $payload.aud -eq "00000003-0000-0000-c000-000000000000" -or
                        $payload.aud -eq "https://graph.microsoft.com"
    $tenantOk = -not $ExpectedTenantId -or $payload.tid -eq $ExpectedTenantId

    return $isGraphAudience -and $tenantOk
  } catch {
    return $false
  }
}

function Get-ValidatedGraphIdentity {
  param([Parameter(Mandatory)] $Request, [string]$ExpectedTenantId)

  $token = Get-BearerToken -Request $Request
  if (-not $token) {
    throw [System.UnauthorizedAccessException]::new("Authorization header manquant ou invalide.")
  }

  if (-not (Test-QuickJwtSanityCheck -Token $token -ExpectedTenantId $ExpectedTenantId)) {
    throw [System.UnauthorizedAccessException]::new("Token rejeté (audience/tenant inattendu).")
  }

  try {
    $me = Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/me" `
      -Headers @{ Authorization = "Bearer $token" }
  } catch {
    throw [System.UnauthorizedAccessException]::new("Token rejeté par Microsoft Graph.")
  }

  if (-not $me.id) {
    throw [System.UnauthorizedAccessException]::new("Réponse Graph invalide (id manquant).")
  }

  return $me
}
