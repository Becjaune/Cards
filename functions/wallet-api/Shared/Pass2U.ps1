# ATTENTION — schéma non vérifié : le plan d'implémentation impose explicitement de confirmer
# l'endpoint exact, le format d'authentification et le payload/réponse réels sur
# https://www.pass2u.net/documentation avant mise en production (compte Pass2U propre à
# l'organisation requis pour lire la doc et tester). Ne pas déployer tel quel : ce fichier
# structure l'appel (env vars, gestion d'erreur, forme de retour attendue) mais NE FAIT PAS
# encore l'appel réseau réel, pour éviter de committer une intégration non vérifiée qui
# semblerait fonctionner alors qu'elle ne l'a jamais été testée contre l'API réelle.

function Invoke-Pass2UCreatePass {
  param(
    [Parameter(Mandatory)] [string]$BarcodeUrl,   # URL stable https://<function>/api/vcard/{id}
    [Parameter(Mandatory)] [hashtable]$Fields      # nom/mobile/email pour le visuel du pass
  )

  $apiKey = $env:PASS2U_API_KEY
  $templateId = $env:PASS2U_TEMPLATE_ID

  if (-not $apiKey -or -not $templateId) {
    throw "PASS2U_API_KEY / PASS2U_TEMPLATE_ID non configurés."
  }

  throw "Invoke-Pass2UCreatePass n'est pas encore implémenté : vérifier l'endpoint, le format " +
        "d'authentification et le schéma de payload/réponse dans la documentation Pass2U " +
        "(https://www.pass2u.net/documentation) avant de coder cet appel, puis retourner un " +
        "objet { walletUrl = <url renvoyée par Pass2U> }."

  # Squelette attendu une fois le contrat d'API confirmé :
  #
  # $body = @{
  #   templateId = $templateId
  #   barcode    = $BarcodeUrl
  #   fields     = @{
  #     name   = $Fields.displayName
  #     mobile = $Fields.mobilePhone
  #     email  = $Fields.email
  #   }
  # } | ConvertTo-Json -Depth 5
  #
  # $response = Invoke-RestMethod -Method Post -Uri "https://<endpoint réel Pass2U>" `
  #   -Headers @{ Authorization = "Bearer $apiKey" } `
  #   -ContentType "application/json" -Body $body
  #
  # return @{ walletUrl = $response.<champ réel de la réponse> }
}
